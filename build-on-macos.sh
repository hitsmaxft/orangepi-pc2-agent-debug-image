#!/bin/bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=image.conf
. "$PROJECT_DIR/image.conf"
OUTPUT_DIR=${OUTPUT_DIR:-$PROJECT_DIR/output}
PUBLIC_KEY=${1:-${SSH_PUBLIC_KEY_FILE:-}}
OUTPUT_IMG="$OUTPUT_DIR/$BASE_NAME-usb-debug.img"
CONTAINER_NAME=opi-image-build-$$

cleanup() {
    container stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    container delete "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v container >/dev/null || { echo "Apple container CLI is required" >&2; exit 1; }
[[ -n "$PUBLIC_KEY" && -s "$PUBLIC_KEY" ]] || {
    echo "set SSH_PUBLIC_KEY_FILE in .envrc or pass a public-key path" >&2
    exit 1
}
if [[ -e "$OUTPUT_IMG" && ${FORCE:-0} != 1 ]]; then
    echo "$OUTPUT_IMG already exists; set FORCE=1 to rebuild" >&2
    exit 1
fi

SOURCE_XZ=$("$PROJECT_DIR/download-base-image.sh")
mkdir -p "$OUTPUT_DIR"
xz -dc "$SOURCE_XZ" >"$OUTPUT_IMG"
cp -p "$PUBLIC_KEY" "$OUTPUT_DIR/authorized_key.pub"

container run --name "$CONTAINER_NAME" --cpus 6 --memory 8G \
    --mount "type=bind,source=$PROJECT_DIR,target=/work" \
    docker.io/library/debian:trixie-slim \
    env IMAGE_SIZE="$IMAGE_SIZE" TARGET_USER="$TARGET_USER" TARGET_HOSTNAME="$TARGET_HOSTNAME" \
    UV_VERSION="$UV_VERSION" PYTHON_VERSION="$PYTHON_VERSION" PACKAGES_FILE=/work/packages.txt \
    bash /work/customize-image.sh "/work/output/$(basename "$OUTPUT_IMG")" /work/output/authorized_key.pub
container delete "$CONTAINER_NAME" >/dev/null

CONTAINER_NAME=opi-image-verify-$$
container run --name "$CONTAINER_NAME" --cpus 4 --memory 4G \
    --mount "type=bind,source=$PROJECT_DIR,target=/work" \
    docker.io/library/debian:trixie-slim bash -lc \
    "apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends e2fsprogs util-linux openssh-client zerofree xz-utils >/dev/null && PACKAGES_FILE=/work/packages.txt /work/verify-image.sh /work/output/$(basename "$OUTPUT_IMG") /work/output/authorized_key.pub && /work/compress-image.sh /work/output/$(basename "$OUTPUT_IMG") /work/output/SHA256SUMS"
container delete "$CONTAINER_NAME" >/dev/null

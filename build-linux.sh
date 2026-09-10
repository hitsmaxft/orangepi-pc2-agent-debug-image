#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=image.conf
. "$PROJECT_DIR/image.conf"
OUTPUT_DIR=${OUTPUT_DIR:-$PROJECT_DIR/output}
SSH_PUBLIC_KEY_FILE=${SSH_PUBLIC_KEY_FILE:-}
OUTPUT_IMG="$OUTPUT_DIR/$BASE_NAME-usb-debug.img"

[[ $(uname -m) == aarch64 || $(uname -m) == arm64 ]] || {
    echo "build-linux.sh requires an ARM64 Linux host because it chroots into the image" >&2
    exit 1
}
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run with sudo -E" >&2; exit 1; }
[[ -n "$SSH_PUBLIC_KEY_FILE" && -s "$SSH_PUBLIC_KEY_FILE" ]] || {
    echo "SSH_PUBLIC_KEY_FILE must point to an OpenSSH public key" >&2
    exit 1
}

SOURCE_XZ=$("$PROJECT_DIR/download-base-image.sh")
mkdir -p "$OUTPUT_DIR"
if [[ -e "$OUTPUT_IMG" && ${FORCE:-0} != 1 ]]; then
    echo "$OUTPUT_IMG already exists; set FORCE=1 to rebuild" >&2
    exit 1
fi
xz -dc "$SOURCE_XZ" >"$OUTPUT_IMG"

IMAGE_SIZE="${IMAGE_SIZE}" TARGET_USER="${TARGET_USER}" TARGET_HOSTNAME="${TARGET_HOSTNAME}" \
UV_VERSION="${UV_VERSION}" PYTHON_VERSION="${PYTHON_VERSION}" \
PACKAGES_FILE="$PROJECT_DIR/packages.txt" \
    "$PROJECT_DIR/customize-image.sh" "$OUTPUT_IMG" "$SSH_PUBLIC_KEY_FILE"
PACKAGES_FILE="$PROJECT_DIR/packages.txt" \
    "$PROJECT_DIR/verify-image.sh" "$OUTPUT_IMG" "$SSH_PUBLIC_KEY_FILE"
"$PROJECT_DIR/compress-image.sh" "$OUTPUT_IMG" "$OUTPUT_DIR/SHA256SUMS"

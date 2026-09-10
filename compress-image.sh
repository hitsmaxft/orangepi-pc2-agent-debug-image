#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE=${1:?usage: compress-image.sh IMAGE [CHECKSUM_FILE]}
CHECKSUM_FILE=${2:-$(dirname "$IMAGE")/SHA256SUMS}
LOOPDEV=

cleanup() {
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV" 2>/dev/null || true
}
trap cleanup EXIT

for command in e2fsck losetup zerofree xz sha256sum; do
    command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

LOOPDEV=$(losetup --find --show --partscan "$IMAGE")
ROOT_PART="${LOOPDEV}p1"
e2fsck -fy "$ROOT_PART"
zerofree "$ROOT_PART"
losetup -d "$LOOPDEV"
LOOPDEV=

xz -T0 -3 --keep --force "$IMAGE"
xz -t "$IMAGE.xz"
(
    cd "$(dirname "$IMAGE")"
    sha256sum "$(basename "$IMAGE.xz")" >"$CHECKSUM_FILE"
)
cat "$CHECKSUM_FILE"

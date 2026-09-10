#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=image.conf
. "$PROJECT_DIR/image.conf"
OUTPUT_DIR=${OUTPUT_DIR:-$PROJECT_DIR/output}
SOURCE_XZ="$OUTPUT_DIR/$BASE_NAME.img.xz"

mkdir -p "$OUTPUT_DIR"
if [[ ! -f "$SOURCE_XZ" ]]; then
    curl -fL --retry 5 --retry-delay 2 -o "$SOURCE_XZ.part" "$BASE_URL"
    mv "$SOURCE_XZ.part" "$SOURCE_XZ"
fi
if command -v sha256sum >/dev/null; then
    printf '%s  %s\n' "$BASE_SHA256" "$SOURCE_XZ" | sha256sum -c - >&2
else
    printf '%s  %s\n' "$BASE_SHA256" "$SOURCE_XZ" | shasum -a 256 -c - >&2
fi
printf '%s\n' "$SOURCE_XZ"

#!/usr/bin/env bash
set -euo pipefail

# Extract Teclast P20HD official firmware:
# - .rar (Roshal archive) -> Firmware.pac (Spreadtrum/UNISOC container)
# - .pac -> boot.img + dtbo.img + vbmeta*.img (+ recovery.img etc.)
#
# Usage:
#   bash scripts/extract_firmware.sh "/path/to/P20HD(...).rar"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/firmware.rar"
  exit 1
fi

FIRMWARE_RAR="$1"
FW_DIR="$PROJECT_DIR/firmware"
PACEX="$PROJECT_DIR/tools/pacextractor/pacextractor"

mkdir -p "$FW_DIR" "$PROJECT_DIR/backup" "$PROJECT_DIR/extracted"

if [[ ! -f "$FIRMWARE_RAR" ]]; then
  echo "ERROR: Firmware RAR not found: $FIRMWARE_RAR"
  exit 1
fi

if [[ ! -x "$PACEX" ]]; then
  echo "ERROR: pacextractor not built/found: $PACEX"
  echo "Run: bash scripts/devtools.sh"
  exit 1
fi

cd "$FW_DIR"

echo "==> Copying firmware archive into firmware/..."
RAR_BASENAME="$(basename "$FIRMWARE_RAR")"
cp -f "$FIRMWARE_RAR" "$RAR_BASENAME"

EXTRACT_DIR="$FW_DIR/extracted_rar"
OUT_DIR="$FW_DIR/extracted_pac"

echo "==> Extracting RAR (Roshal archive) with unrar..."
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unrar x -o+ "$RAR_BASENAME" "$EXTRACT_DIR/" > /dev/null

echo "==> Locating PAC (Spreadtrum/UNISOC firmware container)..."
PAC_FILE="$(find "$EXTRACT_DIR" -type f -iname '*.pac' | head -n 1 || true)"
if [[ -z "$PAC_FILE" ]]; then
  echo "ERROR: No .pac found inside extracted RAR."
  exit 2
fi
echo "PAC: $PAC_FILE"

echo "==> Extracting PAC with pacextractor..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

pushd "$OUT_DIR" > /dev/null
"$PACEX" "$PAC_FILE" .
popd > /dev/null

echo "==> Copying boot-critical images into backup/..."
cp -f "$OUT_DIR/boot.img" "$PROJECT_DIR/backup/boot-stock.img"
cp -f "$OUT_DIR/dtbo.img" "$PROJECT_DIR/backup/" 2>/dev/null || true

shopt -s nullglob
vbmetas=( "$OUT_DIR"/vbmeta*.img "$OUT_DIR"/vbmeta-*.img )
if [[ ${#vbmetas[@]} -gt 0 ]]; then
  cp -f "${vbmetas[@]}" "$PROJECT_DIR/backup/"
fi
shopt -u nullglob

echo "==> Result backup/:"
ls -lh "$PROJECT_DIR/backup" | head -n 80
file "$PROJECT_DIR/backup/boot-stock.img"

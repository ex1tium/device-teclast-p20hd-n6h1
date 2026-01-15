#!/usr/bin/env bash
set -euo pipefail

# Unpack boot image using AIK (Android Image Kitchen — boot image unpack/repack toolkit)
# Then extract DTB (Device Tree Blob — hardware description) from boot image
#
# Usage:
#   bash scripts/unpack_and_extract_dtb.sh
#   bash scripts/unpack_and_extract_dtb.sh /path/to/boot.img

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

AIK_DIR="$PROJECT_DIR/AIK"
BOOT_IMG="${1:-$PROJECT_DIR/backup/boot-stock.img}"

OUT_DTB="$PROJECT_DIR/extracted/dtb_from_bootimg"
mkdir -p "$OUT_DTB"

if [[ ! -f "$BOOT_IMG" ]]; then
  echo "ERROR: Missing boot image: $BOOT_IMG"
  exit 1
fi

if [[ ! -d "$AIK_DIR" ]]; then
  echo "ERROR: AIK directory missing: $AIK_DIR"
  echo "Run: bash scripts/devtools.sh"
  exit 1
fi

echo "==> Boot image: $BOOT_IMG"
echo "==> AIK dir:    $AIK_DIR"

echo "==> Unpacking boot image with AIK..."
(
  cd "$AIK_DIR"
  # allow AIK to succeed even if it prints harmless warnings
  bash ./unpackimg_x64.sh "$BOOT_IMG" || true
)

echo "==> Listing AIK artifacts..."
ls -lah "$AIK_DIR/split_img" | head -n 80 || true
ls -lah "$AIK_DIR/ramdisk"   | head -n 80 || true

echo "==> Extracting DTB (Device Tree Blob) from FULL boot image (this matches your device)..."
extract-dtb "$BOOT_IMG" -o "$OUT_DTB" || true

if ! compgen -G "$OUT_DTB/*.dtb" >/dev/null; then
  echo "ERROR: No DTB files found in $OUT_DTB"
  echo "This device usually has DTB appended to boot image; verify extract-dtb is installed."
  exit 2
fi

echo "==> Decompiling DTB -> DTS (Device Tree Source)..."
cd "$OUT_DTB"
for dtb in *.dtb; do
  dtc -I dtb -O dts -o "${dtb%.dtb}.dts" "$dtb" || true
done

echo "==> Done. DTB/DTS output:"
ls -lh "$OUT_DTB" | head -n 80

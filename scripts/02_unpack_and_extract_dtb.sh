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

# Copy primary DTB to backup/ for easy reference (postmarketOS porting uses this)
BACKUP_DIR="$PROJECT_DIR/backup"
mkdir -p "$BACKUP_DIR"

# Find the first/primary DTB (typically 00_kernel or first numbered DTB)
PRIMARY_DTB=""
for candidate in "$OUT_DTB"/00_kernel "$OUT_DTB"/01_dtb "$OUT_DTB"/*.dtb; do
  if [[ -f "$candidate" && -s "$candidate" ]]; then
    PRIMARY_DTB="$candidate"
    break
  fi
done

if [[ -n "$PRIMARY_DTB" && -f "$PRIMARY_DTB" ]]; then
  echo "==> Copying primary DTB to backup/dtb-stock-trimmed.dtb"
  cp "$PRIMARY_DTB" "$BACKUP_DIR/dtb-stock-trimmed.dtb"

  # Also decompile to DTS in backup for easy reference
  echo "==> Decompiling backup DTB -> DTS..."
  if command -v dtc >/dev/null 2>&1; then
    dtc -I dtb -O dts -o "$BACKUP_DIR/dtb-stock-trimmed.dts" "$BACKUP_DIR/dtb-stock-trimmed.dtb" 2>/dev/null || true
  else
    # Fallback: look for existing DTS from extraction
    EXISTING_DTS=$(find "$OUT_DTB" -name "*.dts" -type f | head -1)
    if [[ -n "$EXISTING_DTS" && -f "$EXISTING_DTS" ]]; then
      echo "[*] dtc not found, copying existing DTS: $EXISTING_DTS"
      cp "$EXISTING_DTS" "$BACKUP_DIR/dtb-stock-trimmed.dts"
    else
      echo "[!] dtc not found and no existing DTS to copy"
    fi
  fi

  echo "==> Backup DTB files:"
  ls -lh "$BACKUP_DIR"/dtb-stock-trimmed.* 2>/dev/null || true
else
  echo "[!] Warning: Could not identify primary DTB to copy to backup/"
fi

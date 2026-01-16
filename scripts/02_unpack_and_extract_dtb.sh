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

# Find the first/primary DTB file (must be .dtb extension, NOT 00_kernel which is the kernel image)
PRIMARY_DTB=""
PRIMARY_DTS=""
for candidate in "$OUT_DTB"/*.dtb; do
  if [[ -f "$candidate" && -s "$candidate" ]]; then
    PRIMARY_DTB="$candidate"
    # Check if matching DTS exists
    candidate_dts="${candidate%.dtb}.dts"
    [[ -f "$candidate_dts" ]] && PRIMARY_DTS="$candidate_dts"
    break
  fi
done

if [[ -n "$PRIMARY_DTB" && -f "$PRIMARY_DTB" ]]; then
  echo "==> Copying primary DTB to backup/dtb-stock-trimmed.dtb"
  cp "$PRIMARY_DTB" "$BACKUP_DIR/dtb-stock-trimmed.dtb"

  # Copy or generate DTS in backup for easy reference
  echo "==> Creating backup DTS..."
  if [[ -n "$PRIMARY_DTS" && -f "$PRIMARY_DTS" ]]; then
    # Prefer existing DTS (already decompiled during extraction)
    echo "[*] Copying existing DTS: $PRIMARY_DTS"
    cp "$PRIMARY_DTS" "$BACKUP_DIR/dtb-stock-trimmed.dts"
  elif command -v dtc >/dev/null 2>&1; then
    # Decompile from DTB
    echo "[*] Decompiling DTB -> DTS..."
    dtc -I dtb -O dts -o "$BACKUP_DIR/dtb-stock-trimmed.dts" "$BACKUP_DIR/dtb-stock-trimmed.dtb" 2>/dev/null || true
  else
    echo "[!] No existing DTS and dtc not found - DTS will be missing"
  fi

  echo "==> Backup DTB/DTS files:"
  ls -lh "$BACKUP_DIR"/dtb-stock-trimmed.* 2>/dev/null || true
else
  echo "[!] Warning: No .dtb files found in $OUT_DTB"
fi

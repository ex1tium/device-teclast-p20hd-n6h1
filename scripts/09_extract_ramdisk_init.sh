#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

AIK_RAMDISK="${1:-$PROJECT_DIR/AIK/ramdisk}"
OUTDIR="${2:-$PROJECT_DIR/extracted/ramdisk_init}"

INITDIR="$OUTDIR/init"
FSTABDIR="$OUTDIR/fstab"
UEVENTDDIR="$OUTDIR/ueventd"

mkdir -p "$INITDIR" "$FSTABDIR" "$UEVENTDDIR"

if [[ ! -d "$AIK_RAMDISK" ]]; then
  echo "ERROR: AIK ramdisk directory not found: $AIK_RAMDISK"
  echo "Hint: run scripts/02_unpack_and_extract_dtb.sh first (AIK unpack step creates ramdisk/)."
  exit 1
fi

echo "[*] AIK ramdisk: $AIK_RAMDISK"
echo "[*] Output dir:  $OUTDIR"

# Idempotent: clear previous copies only (not entire OUTDIR)
rm -f "$INITDIR"/* "$FSTABDIR"/* "$UEVENTDDIR"/* 2>/dev/null || true

shopt -s nullglob

# Copy init*.rc
for f in "$AIK_RAMDISK"/init*.rc; do
  cp -a "$f" "$INITDIR/"
done

# Copy fstab.*
for f in "$AIK_RAMDISK"/fstab*; do
  cp -a "$f" "$FSTABDIR/"
done

# Copy ueventd*.rc
for f in "$AIK_RAMDISK"/ueventd*.rc; do
  cp -a "$f" "$UEVENTDDIR/"
done

shopt -u nullglob

# Create index report
INDEX="$OUTDIR/ramdisk_index.txt"
{
  echo "=== ramdisk init extraction index ==="
  echo "Source: $AIK_RAMDISK"
  echo "Output: $OUTDIR"
  echo
  echo "--- init scripts (init*.rc) ---"
  ls -1 "$INITDIR" 2>/dev/null || true
  echo
  echo "--- fstab files (fstab*) ---"
  ls -1 "$FSTABDIR" 2>/dev/null || true
  echo
  echo "--- ueventd rules (ueventd*.rc) ---"
  ls -1 "$UEVENTDDIR" 2>/dev/null || true
  echo
  echo "--- line counts ---"
  for f in "$INITDIR"/* "$FSTABDIR"/* "$UEVENTDDIR"/*; do
    [[ -f "$f" ]] || continue
    printf "%7s  %s\n" "$(wc -l < "$f")" "$(basename "$f")"
  done
  echo
  echo "--- quick grep hints ---"
  echo "  grep -R \"on init\" -n $INITDIR"
  echo "  grep -R \"service \" -n $INITDIR"
  echo "  grep -R \"mount_all\" -n $INITDIR"
  echo "  grep -R \"first_stage_mount\" -n $FSTABDIR"
  echo "  grep -R \"firmware\" -n $INITDIR $UEVENTDDIR"
  echo "  grep -R \"chmod\" -n $UEVENTDDIR"
} > "$INDEX"

echo
echo "[*] Done. Index written:"
echo "    $INDEX"
echo
echo "[*] Output tree:"
find "$OUTDIR" -maxdepth 2 -type f | sed 's|^'"$PROJECT_DIR/"'||' | head -n 160

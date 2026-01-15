#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTDIR="$PROJECT_DIR/extracted/kernel_info"
mkdir -p "$OUTDIR"

AIK_SPLIT="$PROJECT_DIR/AIK/split_img"
if [[ ! -d "$AIK_SPLIT" ]]; then
  echo "ERROR: AIK split_img missing: $AIK_SPLIT"
  echo "Run scripts/02_unpack_and_extract_dtb.sh first."
  exit 1
fi

KERNEL_FILE="$(ls "$AIK_SPLIT"/*zImage* "$AIK_SPLIT"/*kernel* 2>/dev/null | head -n 1 || true)"
if [[ -z "$KERNEL_FILE" ]]; then
  echo "ERROR: Could not find kernel file in $AIK_SPLIT"
  exit 2
fi

echo "[*] Kernel file: $KERNEL_FILE"
file "$KERNEL_FILE" | tee "$OUTDIR/kernel_filetype.txt" >/dev/null || true

if ! command -v strings >/dev/null 2>&1; then
  echo "ERROR: strings not found."
  echo "Install: sudo apt install -y binutils"
  exit 3
fi

echo "[*] Extracting Linux version string..."
strings -a "$KERNEL_FILE" | grep -m 1 -E '^Linux version ' | tee "$OUTDIR/linux_version.txt" >/dev/null || true

echo "[*] Extracting androidboot strings..."
strings -a "$KERNEL_FILE" | grep -i 'androidboot' | head -n 200 > "$OUTDIR/androidboot_strings.txt" || true

echo "[*] Checking for appended DTB blobs..."
if command -v extract-dtb >/dev/null 2>&1; then
  DTB_DIR="$OUTDIR/dtb_from_kernel"
  mkdir -p "$DTB_DIR"
  extract-dtb "$KERNEL_FILE" -o "$DTB_DIR" >/dev/null 2>&1 || true
  COUNT="$(find "$DTB_DIR" -maxdepth 1 -type f -name '*.dtb' | wc -l | tr -d ' ')"
  echo "$COUNT" | tee "$OUTDIR/appended_dtb_count.txt" >/dev/null
else
  echo "[!] extract-dtb not installed; skipping DTB scan." | tee "$OUTDIR/appended_dtb_count.txt"
fi

echo "[*] Done. Output in: $OUTDIR"
ls -lh "$OUTDIR" | head -n 80

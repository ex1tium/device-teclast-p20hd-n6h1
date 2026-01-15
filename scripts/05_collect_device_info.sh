#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTDIR="$PROJECT_DIR/device-info"
mkdir -p "$OUTDIR"

echo "[*] Writing device info into: $OUTDIR"

# Boot image cmdline (offline)
CMDLINE_FILE="$PROJECT_DIR/AIK/split_img/boot-stock.img-cmdline"
if [[ -f "$CMDLINE_FILE" ]]; then
  cat "$CMDLINE_FILE" | tee "$OUTDIR/bootimg_cmdline.txt"
else
  echo "[!] Missing $CMDLINE_FILE (run scripts/02_unpack_and_extract_dtb.sh first?)" | tee "$OUTDIR/bootimg_cmdline.txt"
fi

# ADB online info (optional)
if ! command -v adb >/dev/null 2>&1; then
  echo "[!] adb not found, skipping runtime collection."
  exit 0
fi

echo "[*] adb devices:"
adb devices -l | tee "$OUTDIR/adb_devices.txt" || true

STATE="$(adb get-state 2>/dev/null || true)"
if [[ "$STATE" != "device" ]]; then
  echo "[!] No connected device in 'device' state. Skipping adb pulls."
  exit 0
fi

echo "[*] Collecting getprop..."
adb shell getprop | tee "$OUTDIR/getprop_full.txt" >/dev/null || true

echo "[*] Collecting boot/product props subset..."
adb shell getprop \
  | grep -E '\[(ro\.boot|ro\.hardware|ro\.product|androidboot)\.' \
  | tee "$OUTDIR/getprop_boot_product_subset.txt" >/dev/null || true

echo "[*] Collecting uname/proc version..."
adb shell uname -a | tee "$OUTDIR/uname_a.txt" >/dev/null || true
adb shell cat /proc/version | tee "$OUTDIR/proc_version.txt" >/dev/null || true

echo "[*] Attempting /proc/cmdline (may be blocked on locked user builds)..."
adb shell cat /proc/cmdline | tee "$OUTDIR/proc_cmdline.txt" >/dev/null || true

echo
echo "[*] Done."

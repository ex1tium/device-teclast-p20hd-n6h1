#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 10_fastboot_info.sh
#
# Collect fastboot bootloader information and optionally attempt unlock.
# This script reboots the device to fastboot mode, collects data, then
# reboots back to Android.
#
# Usage:
#   bash scripts/11_fastboot_info.sh              # Collect info only
#   bash scripts/11_fastboot_info.sh --unlock     # Collect + attempt unlock
#
# Output:
#   device-info/fastboot_getvar_all.txt    - All fastboot variables
#   device-info/fastboot_partitions.txt    - Partition list (if supported)
#   device-info/fastboot_unlock_status.txt - Unlock attempt result (if --unlock)
#
# WARNING: Bootloader unlock WIPES ALL USER DATA on most devices!
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTDIR="$PROJECT_DIR/device-info"
mkdir -p "$OUTDIR"

# CLI flags
ATTEMPT_UNLOCK=0
SKIP_REBOOT_BACK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unlock) ATTEMPT_UNLOCK=1; shift ;;
    --no-reboot) SKIP_REBOOT_BACK=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--unlock] [--no-reboot]"
      echo ""
      echo "Options:"
      echo "  --unlock     Attempt to unlock bootloader after collecting info"
      echo "  --no-reboot  Stay in fastboot mode (don't reboot to Android)"
      echo ""
      echo "WARNING: --unlock will WIPE ALL USER DATA!"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()  { echo "[*] $*"; }
ok()    { echo "[+] $*"; }
warn()  { echo "[!] $*"; }
err()   { echo "[ERROR] $*"; }

wait_for_fastboot() {
  local timeout="${1:-60}"
  local elapsed=0
  info "Waiting for fastboot device (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    if fastboot devices 2>/dev/null | grep -q 'fastboot'; then
      ok "Fastboot device detected"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    printf "."
  done
  echo ""
  err "Timeout waiting for fastboot device"
  return 1
}

wait_for_adb() {
  local timeout="${1:-90}"
  local elapsed=0
  info "Waiting for ADB device (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    local state
    state=$(adb get-state 2>/dev/null || true)
    if [[ "$state" == "device" ]]; then
      ok "ADB device detected"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
    printf "."
  done
  echo ""
  warn "Timeout waiting for ADB - device may still be booting"
  return 1
}

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
if ! command -v fastboot >/dev/null 2>&1; then
  err "fastboot not found in PATH"
  echo "Install: sudo apt install android-sdk-platform-tools"
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  err "adb not found in PATH"
  echo "Install: sudo apt install android-sdk-platform-tools"
  exit 1
fi

# -----------------------------------------------------------------------------
# Check current device state
# -----------------------------------------------------------------------------
info "Checking device connection..."

CURRENT_STATE=""
if fastboot devices 2>/dev/null | grep -q 'fastboot'; then
  CURRENT_STATE="fastboot"
  ok "Device already in fastboot mode"
elif adb get-state 2>/dev/null | grep -q 'device'; then
  CURRENT_STATE="adb"
  ok "Device connected via ADB"
else
  err "No device detected via ADB or fastboot"
  echo ""
  echo "Make sure:"
  echo "  1. Device is connected via USB"
  echo "  2. USB debugging is enabled (Settings > Developer Options)"
  echo "  3. You authorized the USB debugging prompt on the device"
  echo ""
  echo "Or manually boot to fastboot:"
  echo "  - Power off device"
  echo "  - Hold Volume Down + Power until fastboot screen appears"
  exit 1
fi

# -----------------------------------------------------------------------------
# Reboot to fastboot if needed
# -----------------------------------------------------------------------------
if [[ "$CURRENT_STATE" == "adb" ]]; then
  info "Rebooting device to fastboot/bootloader mode..."
  adb reboot bootloader

  if ! wait_for_fastboot 60; then
    err "Failed to enter fastboot mode"
    echo ""
    echo "Try manually:"
    echo "  1. Power off device"
    echo "  2. Hold Volume Down + Power"
    echo "  3. Re-run this script"
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Collect fastboot information
# -----------------------------------------------------------------------------
info "Collecting fastboot variables..."

# Get all variables
{
  echo "# Fastboot Variables"
  echo "# Generated: $(date -Is)"
  echo "# Device: Teclast P20HD (Unisoc SC9863A)"
  echo ""
  fastboot getvar all 2>&1 || true
} | tee "$OUTDIR/fastboot_getvar_all.txt"

ok "Saved to: $OUTDIR/fastboot_getvar_all.txt"

# Try to get partition list (not all bootloaders support this)
info "Attempting to list partitions..."
{
  echo "# Fastboot Partition List"
  echo "# Generated: $(date -Is)"
  echo ""
  fastboot getvar partition-type:boot 2>&1 || true
  fastboot getvar partition-size:boot 2>&1 || true
  fastboot getvar partition-type:recovery 2>&1 || true
  fastboot getvar partition-size:recovery 2>&1 || true
  fastboot getvar partition-type:super 2>&1 || true
  fastboot getvar partition-size:super 2>&1 || true
  fastboot getvar partition-type:userdata 2>&1 || true
  fastboot getvar partition-size:userdata 2>&1 || true
  fastboot getvar partition-type:vbmeta 2>&1 || true
  fastboot getvar partition-size:vbmeta 2>&1 || true
} | tee "$OUTDIR/fastboot_partitions.txt"

# -----------------------------------------------------------------------------
# Parse unlock status from collected data
# -----------------------------------------------------------------------------
info "Analyzing bootloader status..."

UNLOCKED="unknown"
UNLOCK_ALLOWED="unknown"

if grep -qi "unlocked.*yes\|unlocked.*true\|unlocked:.*yes" "$OUTDIR/fastboot_getvar_all.txt" 2>/dev/null; then
  UNLOCKED="yes"
elif grep -qi "unlocked.*no\|unlocked.*false\|unlocked:.*no" "$OUTDIR/fastboot_getvar_all.txt" 2>/dev/null; then
  UNLOCKED="no"
fi

if grep -qi "unlock.*allowed\|flashing.*unlock.*allowed\|oem.*unlock.*true" "$OUTDIR/fastboot_getvar_all.txt" 2>/dev/null; then
  UNLOCK_ALLOWED="yes"
elif grep -qi "unlock.*not.*allowed\|flashing.*unlock.*not\|oem.*unlock.*false" "$OUTDIR/fastboot_getvar_all.txt" 2>/dev/null; then
  UNLOCK_ALLOWED="no"
fi

echo ""
echo "========================================"
echo "Bootloader Status Analysis"
echo "========================================"
echo "  Currently unlocked: $UNLOCKED"
echo "  Unlock allowed:     $UNLOCK_ALLOWED"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# Attempt unlock if requested
# -----------------------------------------------------------------------------
if [[ "$ATTEMPT_UNLOCK" -eq 1 ]]; then
  echo ""
  warn "=========================================="
  warn "  BOOTLOADER UNLOCK REQUESTED"
  warn "=========================================="
  warn ""
  warn "  THIS WILL WIPE ALL USER DATA!"
  warn ""
  warn "  - All apps, photos, and settings will be DELETED"
  warn "  - Device will factory reset"
  warn "  - This may void warranty"
  warn ""
  warn "=========================================="
  echo ""

  read -r -p "Type 'UNLOCK' to proceed, or anything else to skip: " confirm

  if [[ "$confirm" == "UNLOCK" ]]; then
    info "Attempting bootloader unlock..."

    {
      echo "# Bootloader Unlock Attempt"
      echo "# Generated: $(date -Is)"
      echo ""

      echo "=== Trying: fastboot flashing unlock ==="
      fastboot flashing unlock 2>&1 || true
      echo ""

      echo "=== Trying: fastboot oem unlock ==="
      fastboot oem unlock 2>&1 || true
      echo ""

      echo "=== Post-unlock status ==="
      fastboot getvar unlocked 2>&1 || true
      fastboot getvar all 2>&1 || true
    } | tee "$OUTDIR/fastboot_unlock_status.txt"

    ok "Unlock attempt logged to: $OUTDIR/fastboot_unlock_status.txt"

    echo ""
    echo "Check the output above for results."
    echo "If you see prompts on the device screen, follow them."
    echo ""
  else
    info "Unlock skipped by user"
  fi
fi

# -----------------------------------------------------------------------------
# Reboot back to Android
# -----------------------------------------------------------------------------
if [[ "$SKIP_REBOOT_BACK" -eq 0 ]]; then
  info "Rebooting device back to Android..."
  fastboot reboot

  echo ""
  info "Device is rebooting. It may take 1-2 minutes to fully boot."

  if wait_for_adb 120; then
    ok "Device is back online"
  else
    warn "Device may still be booting - check manually"
  fi
else
  info "Staying in fastboot mode (--no-reboot specified)"
  echo ""
  echo "To reboot manually: fastboot reboot"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Collection Complete"
echo "========================================"
echo ""
echo "Output files:"
ls -la "$OUTDIR"/fastboot_*.txt 2>/dev/null || echo "  (none)"
echo ""
echo "Key findings:"
echo "  - Bootloader unlocked: $UNLOCKED"
echo "  - Unlock allowed: $UNLOCK_ALLOWED"
echo ""

if [[ "$UNLOCKED" == "no" && "$UNLOCK_ALLOWED" == "no" ]]; then
  warn "Bootloader unlock may not be supported via standard fastboot commands."
  echo ""
  echo "For Unisoc devices, you may need:"
  echo "  1. Enable OEM unlock in Developer Options first"
  echo "  2. Use SPD Research Tool (Windows)"
  echo "  3. Check XDA forums for device-specific methods"
fi

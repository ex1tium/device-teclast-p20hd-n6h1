#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 12_unlock_bootloader.sh
#
# Unlock bootloader on Unisoc SC9863A devices using the identifier token
# + signature method. This is required before flashing custom boot images.
#
# REQUIREMENTS:
#   1. Linux x86_64 system (the modified fastboot binary is x86_64 only)
#   2. Download the Hovatek modified_fastboot.zip from:
#      https://www.hovatek.com/forum/thread-32287.html
#   3. Place the zip file at: tools/[Hovatek] modified_fastboot.zip
#   4. Device with USB debugging enabled
#   5. OEM unlock toggle enabled (Settings > Developer Options > OEM unlocking)
#
# WARNING: UNLOCKING THE BOOTLOADER WILL:
#   - WIPE ALL USER DATA (factory reset)
#   - May void warranty
#   - Allow flashing unsigned boot images
#
# Usage:
#   bash scripts/12_unlock_bootloader.sh              # Interactive mode
#   bash scripts/12_unlock_bootloader.sh --check      # Check status only
#   bash scripts/12_unlock_bootloader.sh --no-reboot  # Stay in fastboot after
#
# Output:
#   device-info/bootloader_unlock.log     - Full unlock attempt log
#   device-info/identifier_token.txt      - Device identifier token
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS_DIR="${PROJECT_DIR}/tools"
OUTDIR="${PROJECT_DIR}/device-info"

# Hovatek package location
HOVATEK_ZIP="${TOOLS_DIR}/[Hovatek] modified_fastboot.zip"
HOVATEK_DIR="${TOOLS_DIR}/hovatek_fastboot"

mkdir -p "$OUTDIR"

# -----------------------------------------------------------------------------
# CLI flags
# -----------------------------------------------------------------------------
CHECK_ONLY=0
SKIP_REBOOT=0
FORCE_EXTRACT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      CHECK_ONLY=1; shift ;;
    --no-reboot)  SKIP_REBOOT=1; shift ;;
    --force)      FORCE_EXTRACT=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]

Options:
  --check       Check bootloader status only (no unlock attempt)
  --no-reboot   Stay in fastboot mode after unlock
  --force       Re-extract Hovatek tools even if already present
  -h, --help    Show this help

Prerequisites:
  1. Download modified_fastboot.zip from:
     https://www.hovatek.com/forum/thread-32287.html

  2. Place the zip at:
     tools/[Hovatek] modified_fastboot.zip

  3. Enable OEM unlock toggle on device:
     Settings > Developer Options > OEM unlocking

WARNING: Bootloader unlock WIPES ALL USER DATA!
EOF
      exit 0
      ;;
    *) echo "[ERROR] Unknown option: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# Pretty output helpers
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  RESET=$'\033[0m'
else
  BOLD="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

info()  { echo "${BLUE}[*]${RESET} $*"; }
ok()    { echo "${GREEN}[+]${RESET} $*"; }
warn()  { echo "${YELLOW}[!]${RESET} $*"; }
err()   { echo "${RED}[ERROR]${RESET} $*"; }
hr()    { echo "────────────────────────────────────────────────────────────"; }

# -----------------------------------------------------------------------------
# Architecture check
# -----------------------------------------------------------------------------
check_architecture() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" != "x86_64" ]]; then
    err "This script requires x86_64 Linux"
    echo ""
    echo "The Hovatek modified fastboot binary is compiled for x86_64 only."
    echo "Your architecture: $arch"
    echo ""
    echo "Options:"
    echo "  1. Run this on an x86_64 Linux machine"
    echo "  2. Use an x86_64 VM or container"
    echo "  3. Boot from an Ubuntu x86_64 Live USB"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Dependency checks
# -----------------------------------------------------------------------------
check_dependencies() {
  local missing=()

  if ! command -v adb >/dev/null 2>&1; then
    missing+=("adb")
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    missing+=("openssl")
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    missing+=("unzip")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing dependencies: ${missing[*]}"
    echo ""
    echo "Install with:"
    echo "  sudo apt install android-sdk-platform-tools openssl unzip"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Extract Hovatek tools
# -----------------------------------------------------------------------------
extract_hovatek_tools() {
  if [[ ! -f "$HOVATEK_ZIP" ]]; then
    err "Hovatek modified_fastboot.zip not found!"
    echo ""
    echo "Please download from:"
    echo "  ${BOLD}https://www.hovatek.com/forum/thread-32287.html${RESET}"
    echo ""
    echo "Then place the zip file at:"
    echo "  ${BOLD}${HOVATEK_ZIP}${RESET}"
    echo ""
    echo "This package contains:"
    echo "  - Modified fastboot binary with unlock_bootloader support"
    echo "  - Signature generation script"
    echo "  - RSA key for Unisoc/Spreadtrum devices"
    exit 1
  fi

  if [[ -d "$HOVATEK_DIR" && "$FORCE_EXTRACT" -eq 0 ]]; then
    info "Hovatek tools already extracted"
    return 0
  fi

  info "Extracting Hovatek tools..."
  rm -rf "$HOVATEK_DIR"
  mkdir -p "$HOVATEK_DIR"

  unzip -q "$HOVATEK_ZIP" -d "$HOVATEK_DIR"

  # Handle nested directory structure from zip
  if [[ -d "${HOVATEK_DIR}/modified_fastboot" ]]; then
    mv "${HOVATEK_DIR}/modified_fastboot"/* "$HOVATEK_DIR/"
    rmdir "${HOVATEK_DIR}/modified_fastboot"
  fi

  # Make binaries executable
  chmod +x "${HOVATEK_DIR}/fastboot" 2>/dev/null || true
  chmod +x "${HOVATEK_DIR}/signidentifier_unlockbootloader.sh" 2>/dev/null || true
  chmod +x "${HOVATEK_DIR}/start.sh" 2>/dev/null || true

  # IMPORTANT: Delete pre-included signature.bin - it's useless!
  # The signature must be generated specifically for YOUR device's identifier token
  if [[ -f "${HOVATEK_DIR}/signature.bin" ]]; then
    rm -f "${HOVATEK_DIR}/signature.bin"
    info "Removed pre-included signature.bin (will generate device-specific one)"
  fi

  # Verify extraction
  if [[ ! -x "${HOVATEK_DIR}/fastboot" ]]; then
    err "Failed to extract fastboot binary"
    exit 1
  fi

  if [[ ! -f "${HOVATEK_DIR}/signidentifier_unlockbootloader.sh" ]]; then
    err "Failed to extract signature script"
    exit 1
  fi

  if [[ ! -f "${HOVATEK_DIR}/rsa4096_vbmeta.pem" ]]; then
    err "Failed to extract RSA key"
    exit 1
  fi

  ok "Hovatek tools extracted to: $HOVATEK_DIR"
}

# -----------------------------------------------------------------------------
# Device connection helpers
# -----------------------------------------------------------------------------
wait_for_fastboot() {
  local timeout="${1:-60}"
  local elapsed=0

  info "Waiting for fastboot device (timeout: ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    if "${HOVATEK_DIR}/fastboot" devices 2>/dev/null | grep -q 'fastboot'; then
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
# Get identifier token
# -----------------------------------------------------------------------------
get_identifier_token() {
  local token_file="${OUTDIR}/identifier_token.txt"
  local raw_output

  # Status messages go to stderr so they don't pollute the return value
  info "Requesting identifier token from bootloader..." >&2

  raw_output=$("${HOVATEK_DIR}/fastboot" oem get_identifier_token 2>&1 || true)

  echo "$raw_output" > "${OUTDIR}/identifier_token_raw.txt"

  # Extract the hex token (line starting with numbers)
  # Format varies but typically a 32-char hex string
  local token
  token=$(echo "$raw_output" | grep -oE '^[0-9A-Fa-f]{16,64}$' | head -1 || true)

  if [[ -z "$token" ]]; then
    # Try alternate extraction (some devices include prefix)
    token=$(echo "$raw_output" | grep -oE '[0-9A-Fa-f]{16,64}' | head -1 || true)
  fi

  if [[ -z "$token" ]]; then
    err "Failed to extract identifier token" >&2
    echo "" >&2
    echo "Raw output saved to: ${OUTDIR}/identifier_token_raw.txt" >&2
    echo "" >&2
    echo "Raw output was:" >&2
    echo "$raw_output" >&2
    return 1
  fi

  echo "$token" > "$token_file"
  ok "Identifier token: $token" >&2
  ok "Saved to: $token_file" >&2

  # Only the token goes to stdout (for capture)
  echo "$token"
}

# -----------------------------------------------------------------------------
# Generate signature
# -----------------------------------------------------------------------------
generate_signature() {
  local token="$1"
  local signature_file="${HOVATEK_DIR}/signature.bin"

  info "Generating unlock signature..."

  # Remove old signature if exists
  rm -f "$signature_file"

  # Run the Spreadtrum signing script
  (
    cd "$HOVATEK_DIR"
    ./signidentifier_unlockbootloader.sh "$token" rsa4096_vbmeta.pem signature.bin
  )

  if [[ ! -f "$signature_file" ]]; then
    err "Failed to generate signature.bin"
    return 1
  fi

  local sig_size
  sig_size=$(stat -c%s "$signature_file" 2>/dev/null || stat -f%z "$signature_file" 2>/dev/null)

  if [[ "$sig_size" -lt 256 ]]; then
    err "Signature file too small ($sig_size bytes) - generation may have failed"
    return 1
  fi

  ok "Signature generated: $signature_file ($sig_size bytes)"
}

# -----------------------------------------------------------------------------
# Perform unlock
# -----------------------------------------------------------------------------
perform_unlock() {
  local signature_file="${HOVATEK_DIR}/signature.bin"

  info "Sending unlock command..."
  echo ""
  warn "╔══════════════════════════════════════════════════════════════╗"
  warn "║  IMPORTANT: Watch your device screen!                        ║"
  warn "║                                                              ║"
  warn "║  When prompted, press VOLUME DOWN to confirm unlock.         ║"
  warn "║  Press VOLUME UP to cancel.                                  ║"
  warn "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Verify signature file exists
  if [[ ! -f "$signature_file" ]]; then
    err "Signature file not found: $signature_file"
    return 1
  fi

  info "Using signature: $signature_file"
  sleep 2

  local result
  result=$("${HOVATEK_DIR}/fastboot" flashing unlock_bootloader "$signature_file" 2>&1 || true)

  echo "$result"
  echo "$result" >> "${OUTDIR}/bootloader_unlock.log"

  # Check for success indicators
  if echo "$result" | grep -qi "OKAY\|success\|unlocked"; then
    return 0
  fi

  # Check for user cancellation
  if echo "$result" | grep -qi "cancel\|abort\|denied"; then
    warn "Unlock was cancelled (user pressed Volume Up or timeout)"
    return 2
  fi

  return 1
}

# -----------------------------------------------------------------------------
# Check unlock status
# -----------------------------------------------------------------------------
check_unlock_status() {
  info "Checking bootloader unlock status..."

  # NOTE: Unisoc/Spreadtrum bootloaders do NOT support standard fastboot variables!
  # Commands like 'getvar unlocked' and 'getvar all' return empty or nothing.
  #
  # Supported Unisoc fastboot commands:
  #   - fastboot oem get_identifier_token  (returns device token for signing)
  #   - fastboot flashing unlock_bootloader signature.bin  (unlock with signature)
  #   - fastboot flashing lock_bootloader  (re-lock)
  #   - fastboot flash <partition> <image>  (standard flashing)
  #   - fastboot reboot  (reboot device)
  #
  # The only reliable way to check lock status is to attempt get_identifier_token:
  # - If it returns a token: bootloader is LOCKED (token needed for unlock)
  # - If it fails/errors: bootloader may be UNLOCKED (or other error)

  local token_output

  info "Attempting to get identifier token (Unisoc-specific check)..."
  token_output=$("${HOVATEK_DIR}/fastboot" oem get_identifier_token 2>&1 || true)

  echo "$token_output"

  # Save for debugging
  echo "$token_output" > "${OUTDIR}/fastboot_identifier_check.txt"

  # Check if we got a valid token (hex string)
  if echo "$token_output" | grep -qE '[0-9A-Fa-f]{16,}'; then
    warn "Bootloader appears LOCKED (identifier token returned)"
    info "Token received - device is ready for unlock process"
    return 1  # Locked
  fi

  # Check for explicit unlock confirmation
  if echo "$token_output" | grep -qi "already.*unlock\|unlocked\|not.*locked"; then
    ok "Bootloader appears UNLOCKED"
    return 0  # Unlocked
  fi

  # Check for failure that might indicate unlocked state
  if echo "$token_output" | grep -qi "fail\|error\|unknown\|not.*support"; then
    warn "Could not get identifier token"
    warn "This may indicate: already unlocked, or unsupported command"
    echo ""
    info "Try the unlock process - if already unlocked, it will indicate so"
    return 2  # Unknown
  fi

  warn "Status check inconclusive (typical for Unisoc)"
  return 2
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
main() {
  hr
  echo "${BOLD}Unisoc SC9863A Bootloader Unlock Tool${RESET}"
  echo "For: Teclast P20HD and similar devices"
  hr
  echo ""

  # Pre-flight checks
  check_architecture
  check_dependencies
  extract_hovatek_tools

  echo ""
  hr

  # Check device connection
  info "Checking device connection..."

  local current_state=""

  if "${HOVATEK_DIR}/fastboot" devices 2>/dev/null | grep -q 'fastboot'; then
    current_state="fastboot"
    ok "Device already in fastboot mode"
  elif adb get-state 2>/dev/null | grep -q 'device'; then
    current_state="adb"
    ok "Device connected via ADB"
  else
    err "No device detected via ADB or fastboot"
    echo ""
    echo "Make sure:"
    echo "  1. Device is connected via USB"
    echo "  2. USB debugging is enabled"
    echo "  3. You authorized the USB debugging prompt"
    echo ""
    echo "Or manually boot to fastboot:"
    echo "  - Power off device"
    echo "  - Hold Volume Down + Power"
    exit 1
  fi

  # Reboot to fastboot if needed
  if [[ "$current_state" == "adb" ]]; then
    info "Rebooting to fastboot/bootloader mode..."
    adb reboot bootloader

    if ! wait_for_fastboot 60; then
      err "Failed to enter fastboot mode"
      exit 1
    fi
  fi

  echo ""
  hr

  # Start logging
  {
    echo "# Bootloader Unlock Log"
    echo "# Device: Teclast P20HD (Unisoc SC9863A)"
    echo "# Date: $(date -Is)"
    echo ""
  } > "${OUTDIR}/bootloader_unlock.log"

  # Check current status
  echo ""
  # Disable exit-on-error temporarily to capture the return code
  # check_unlock_status returns: 0=unlocked, 1=locked, 2=unknown
  local is_unlocked
  set +e
  check_unlock_status 2>&1 | tee -a "${OUTDIR}/bootloader_unlock.log"
  is_unlocked="${PIPESTATUS[0]}"
  set -e

  if [[ "$is_unlocked" -eq 0 ]]; then
    echo ""
    ok "Bootloader is already unlocked!"
    echo ""

    if [[ "$SKIP_REBOOT" -eq 0 ]]; then
      info "Rebooting to Android..."
      "${HOVATEK_DIR}/fastboot" reboot
    fi

    exit 0
  fi

  # Check-only mode exits here
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    echo ""
    info "Check-only mode - not attempting unlock"

    if [[ "$SKIP_REBOOT" -eq 0 ]]; then
      info "Rebooting to Android..."
      "${HOVATEK_DIR}/fastboot" reboot
    fi

    exit 0
  fi

  echo ""
  hr
  echo ""
  warn "╔══════════════════════════════════════════════════════════════╗"
  warn "║                    ${BOLD}WARNING: DATA LOSS${RESET}${YELLOW}                         ║"
  warn "║                                                              ║"
  warn "║  Unlocking the bootloader will FACTORY RESET your device!   ║"
  warn "║                                                              ║"
  warn "║  ALL data will be erased:                                   ║"
  warn "║    - Apps and app data                                      ║"
  warn "║    - Photos, videos, downloads                              ║"
  warn "║    - Accounts and settings                                  ║"
  warn "║                                                              ║"
  warn "║  This action may also void your warranty.                   ║"
  warn "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  read -r -p "Type ${BOLD}UNLOCK${RESET} to proceed, or anything else to abort: " confirm

  if [[ "$confirm" != "UNLOCK" ]]; then
    info "Unlock cancelled by user"

    if [[ "$SKIP_REBOOT" -eq 0 ]]; then
      info "Rebooting to Android..."
      "${HOVATEK_DIR}/fastboot" reboot
    fi

    exit 0
  fi

  echo ""
  hr
  echo ""

  # Get identifier token
  local token
  token=$(get_identifier_token)

  if [[ -z "$token" ]]; then
    err "Failed to get identifier token"
    exit 1
  fi

  echo "" | tee -a "${OUTDIR}/bootloader_unlock.log"
  echo "Identifier Token: $token" | tee -a "${OUTDIR}/bootloader_unlock.log"
  echo "" | tee -a "${OUTDIR}/bootloader_unlock.log"

  # Generate signature
  generate_signature "$token"

  echo ""
  hr
  echo ""

  # Perform unlock
  if perform_unlock; then
    echo ""
    ok "Unlock command sent successfully!"
    echo ""

    # Verify unlock status
    sleep 2
    info "Verifying unlock status..."

    if check_unlock_status; then
      echo ""
      ok "════════════════════════════════════════════════════════════"
      ok "  BOOTLOADER SUCCESSFULLY UNLOCKED!"
      ok "════════════════════════════════════════════════════════════"
      echo ""
      echo "You can now:"
      echo "  1. Flash custom boot images with: fastboot flash boot <image>"
      echo "  2. Boot custom images without flashing: fastboot boot <image>"
      echo "  3. Disable AVB verification if needed"
      echo ""
    else
      warn "Unlock command completed but status unclear"
      warn "Device may need to complete factory reset first"
    fi
  else
    err "Unlock may have failed - check device screen"
  fi

  echo ""
  hr

  # Final reboot
  if [[ "$SKIP_REBOOT" -eq 0 ]]; then
    info "Rebooting device..."
    "${HOVATEK_DIR}/fastboot" reboot

    echo ""
    info "Device is rebooting. First boot after unlock may take longer."
    info "You may need to go through initial Android setup again."
  else
    info "Staying in fastboot mode (--no-reboot specified)"
    echo ""
    echo "To reboot manually: ${HOVATEK_DIR}/fastboot reboot"
  fi

  echo ""
  hr
  echo ""
  info "Unlock log saved to: ${OUTDIR}/bootloader_unlock.log"
  echo ""
}

main "$@"

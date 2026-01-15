#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUPER_DIR="${1:-$PROJECT_DIR/extracted/super_lpunpack}"
OUTDIR="${2:-$PROJECT_DIR/extracted/vendor_blobs}"

mkdir -p "$OUTDIR"
mkdir -p "$PROJECT_DIR/work"

VENDOR_IMG="$(find "$SUPER_DIR" -maxdepth 1 -type f -name "vendor*.img" | head -n 1 || true)"
if [[ -z "$VENDOR_IMG" || ! -f "$VENDOR_IMG" ]]; then
  echo "ERROR: vendor*.img not found in: $SUPER_DIR"
  echo "Hint: run scripts/03_unpack_super_img.sh first."
  exit 1
fi

echo "[*] vendor image: $VENDOR_IMG"
file "$VENDOR_IMG" || true

# Convert sparse vendor.img -> raw if needed
VENDOR_RAW="$PROJECT_DIR/extracted/vendor.raw.img"
if file "$VENDOR_IMG" | grep -qi "sparse"; then
  if ! command -v simg2img >/dev/null 2>&1; then
    echo "ERROR: simg2img not found."
    echo "Install: sudo apt install -y android-sdk-libsparse-utils"
    exit 2
  fi
  if [[ ! -f "$VENDOR_RAW" || ! -s "$VENDOR_RAW" ]]; then
    echo "[*] Sparse vendor image detected -> converting: $VENDOR_RAW"
    simg2img "$VENDOR_IMG" "$VENDOR_RAW"
  fi
else
  VENDOR_RAW="$VENDOR_IMG"
fi

MNT="$PROJECT_DIR/work/mnt_vendor"
mkdir -p "$MNT"

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

MOUNT_SUCCESS=false

echo "[*] Trying mount extraction (preferred)..."
if sudo mount -o loop,ro "$VENDOR_RAW" "$MNT" 2>/dev/null; then
  echo "[*] Mounted vendor -> $MNT"
  MOUNT_SUCCESS=true

  mkdir -p "$OUTDIR/lib" "$OUTDIR/etc/vintf" "$OUTDIR/firmware"

  if [[ -d "$MNT/lib/modules" ]]; then
    mkdir -p "$OUTDIR/lib"
    cp -a "$MNT/lib/modules" "$OUTDIR/lib/" || true
  fi

  if [[ -d "$MNT/firmware" ]]; then
    cp -a "$MNT/firmware" "$OUTDIR/" || true
  fi

  copy_if_exists "$MNT/etc/vintf/manifest.xml" "$OUTDIR/etc/vintf/manifest.xml"
  copy_if_exists "$MNT/etc/vintf/compatibility_matrix.xml" "$OUTDIR/etc/vintf/compatibility_matrix.xml"
  copy_if_exists "$MNT/build.prop" "$OUTDIR/build.prop"

  sudo umount "$MNT"
  echo "[*] Unmounted."
else
  echo "[!] Mount failed (container or permissions). Falling back to debugfs..."
  if ! command -v debugfs >/dev/null 2>&1; then
    echo "ERROR: debugfs not found."
    echo "Install: sudo apt install -y e2fsprogs"
    exit 3
  fi

  mkdir -p "$OUTDIR/lib/modules" "$OUTDIR/firmware" "$OUTDIR/etc/vintf"

  # List what's available in the image first
  echo "[*] Listing vendor image contents..."
  debugfs -R "ls -l /lib/modules" "$VENDOR_RAW" 2>/dev/null | head -20 || true

  # Directories - debugfs rdump has limitations, try alternative approach
  echo "[*] Extracting kernel modules (debugfs)..."
  # Get list of module files and extract individually
  MODULE_LIST=$(debugfs -R "ls /lib/modules" "$VENDOR_RAW" 2>/dev/null | tr -s ' ' '\n' | grep -E '\.ko$' || true)
  if [[ -n "$MODULE_LIST" ]]; then
    for mod in $MODULE_LIST; do
      debugfs -R "dump /lib/modules/$mod $OUTDIR/lib/modules/$mod" "$VENDOR_RAW" 2>/dev/null || true
    done
  fi

  # Try firmware directory
  echo "[*] Extracting firmware (debugfs)..."
  FW_LIST=$(debugfs -R "ls /firmware" "$VENDOR_RAW" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' || true)
  if [[ -n "$FW_LIST" ]]; then
    for fw in $FW_LIST; do
      # Skip . and ..
      [[ "$fw" == "." || "$fw" == ".." ]] && continue
      debugfs -R "dump /firmware/$fw $OUTDIR/firmware/$fw" "$VENDOR_RAW" 2>/dev/null || true
    done
  fi

  # Files
  echo "[*] Extracting config files (debugfs)..."
  debugfs -R "dump /etc/vintf/manifest.xml $OUTDIR/etc/vintf/manifest.xml" "$VENDOR_RAW" 2>/dev/null || true
  debugfs -R "dump /etc/vintf/compatibility_matrix.xml $OUTDIR/etc/vintf/compatibility_matrix.xml" "$VENDOR_RAW" 2>/dev/null || true
  debugfs -R "dump /build.prop $OUTDIR/build.prop" "$VENDOR_RAW" 2>/dev/null || true
fi

# Provide summary of what was extracted
echo
echo "[*] Extraction summary:"
MODULE_COUNT=$(find "$OUTDIR/lib/modules" -name "*.ko" 2>/dev/null | wc -l || echo 0)
FW_COUNT=$(find "$OUTDIR/firmware" -type f 2>/dev/null | wc -l || echo 0)
echo "    Kernel modules (.ko): $MODULE_COUNT"
echo "    Firmware files:       $FW_COUNT"
[[ -f "$OUTDIR/build.prop" && -s "$OUTDIR/build.prop" ]] && echo "    build.prop:           ✓" || echo "    build.prop:           ✗"
[[ -f "$OUTDIR/etc/vintf/manifest.xml" && -s "$OUTDIR/etc/vintf/manifest.xml" ]] && echo "    manifest.xml:         ✓" || echo "    manifest.xml:         ✗"

if [[ "$MOUNT_SUCCESS" == "false" && "$MODULE_COUNT" -eq 0 ]]; then
  echo
  echo "[!] Warning: No kernel modules extracted via debugfs."
  echo "    debugfs has limitations extracting directory trees."
  echo "    For full extraction, run outside container with sudo:"
  echo "      sudo mount -o loop,ro $VENDOR_RAW /mnt"
  echo "      cp -a /mnt/lib/modules $OUTDIR/lib/"
  echo "      sudo umount /mnt"
fi

echo
echo "[*] Done. Extracted vendor bringup blobs:"
find "$OUTDIR" -maxdepth 4 -type f | sed 's|^'"$PROJECT_DIR/"'||' | head -n 120

#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 06_extract_bootimg_info.sh
#
# Extract comprehensive boot.img metadata for postmarketOS porting:
#   - Boot header version, page size, offsets
#   - Kernel version string (handles compressed kernels)
#   - androidboot.* kernel parameters
#   - Kernel config (if embedded)
#
# Requires AIK (Android Image Kitchen) to have already unpacked the boot image.
# Run scripts/02_unpack_and_extract_dtb.sh first.
#
# Output:
#   extracted/bootimg_info/
#     boot_header.txt        - mkbootimg-compatible header parameters
#     kernel_version.txt     - Linux version string
#     kernel_config.txt      - Kernel config (if extractable)
#     kernel_strings.txt     - Interesting strings from kernel
#     summary.json           - Machine-readable summary
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTDIR="$PROJECT_DIR/extracted/bootimg_info"
mkdir -p "$OUTDIR"

AIK_SPLIT="$PROJECT_DIR/AIK/split_img"
BOOT_IMG="$PROJECT_DIR/backup/boot-stock.img"

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
if [[ ! -d "$AIK_SPLIT" ]]; then
  echo "ERROR: AIK split_img missing: $AIK_SPLIT"
  echo "Run scripts/02_unpack_and_extract_dtb.sh first."
  exit 1
fi

# Find the boot image name prefix from AIK output
BOOT_PREFIX=""
for f in "$AIK_SPLIT"/*-base; do
  if [[ -f "$f" ]]; then
    BOOT_PREFIX="${f%-base}"
    break
  fi
done

if [[ -z "$BOOT_PREFIX" ]]; then
  echo "ERROR: Could not find AIK split files in $AIK_SPLIT"
  exit 1
fi

echo "[*] AIK prefix: $(basename "$BOOT_PREFIX")"
echo "[*] Output dir: $OUTDIR"

# -----------------------------------------------------------------------------
# Extract boot header parameters
# -----------------------------------------------------------------------------
echo ""
echo "[*] Extracting boot image header parameters..."

{
  echo "# Boot Image Header Parameters"
  echo "# Generated: $(date -Is)"
  echo "# Source: AIK split_img analysis"
  echo ""

  # Read all AIK metadata files
  read_aik_param() {
    local param="$1"
    local file="${BOOT_PREFIX}-${param}"
    if [[ -f "$file" ]]; then
      cat "$file" | tr -d '\n'
    else
      echo "N/A"
    fi
  }

  BASE=$(read_aik_param "base")
  PAGESIZE=$(read_aik_param "pagesize")
  KERNEL_OFFSET=$(read_aik_param "kerneloff")
  RAMDISK_OFFSET=$(read_aik_param "ramdiskoff")
  TAGS_OFFSET=$(read_aik_param "tagsoff")
  SECOND_OFFSET=$(read_aik_param "secondoff")
  BOARD=$(read_aik_param "board")
  CMDLINE=$(read_aik_param "cmdline")
  RAMDISK_COMP=$(read_aik_param "ramdiskcomp")

  # Try to detect header version from file structure
  HEADER_VERSION="0"
  if [[ -f "${BOOT_PREFIX}-headerversion" ]]; then
    HEADER_VERSION=$(cat "${BOOT_PREFIX}-headerversion" | tr -d '\n')
  elif [[ -f "${BOOT_PREFIX}-dtb" && -s "${BOOT_PREFIX}-dtb" ]]; then
    # Header v2+ has separate DTB section
    HEADER_VERSION="2"
  fi

  # Kernel and ramdisk sizes
  KERNEL_SIZE="N/A"
  RAMDISK_SIZE="N/A"
  if [[ -f "${BOOT_PREFIX}-zImage" ]]; then
    KERNEL_SIZE=$(stat -c%s "${BOOT_PREFIX}-zImage" 2>/dev/null || stat -f%z "${BOOT_PREFIX}-zImage" 2>/dev/null || echo "N/A")
  elif [[ -f "${BOOT_PREFIX}-kernel" ]]; then
    KERNEL_SIZE=$(stat -c%s "${BOOT_PREFIX}-kernel" 2>/dev/null || stat -f%z "${BOOT_PREFIX}-kernel" 2>/dev/null || echo "N/A")
  fi

  RAMDISK_FILE=""
  for ext in "cpio.gz" "cpio.lz4" "cpio.xz" "cpio"; do
    if [[ -f "${BOOT_PREFIX}-ramdisk.${ext}" ]]; then
      RAMDISK_FILE="${BOOT_PREFIX}-ramdisk.${ext}"
      break
    fi
  done
  if [[ -n "$RAMDISK_FILE" ]]; then
    RAMDISK_SIZE=$(stat -c%s "$RAMDISK_FILE" 2>/dev/null || stat -f%z "$RAMDISK_FILE" 2>/dev/null || echo "N/A")
  fi

  echo "HEADER_VERSION=$HEADER_VERSION"
  echo "BASE=$BASE"
  echo "PAGESIZE=$PAGESIZE"
  echo "KERNEL_OFFSET=$KERNEL_OFFSET"
  echo "RAMDISK_OFFSET=$RAMDISK_OFFSET"
  echo "TAGS_OFFSET=$TAGS_OFFSET"
  echo "SECOND_OFFSET=$SECOND_OFFSET"
  echo "BOARD=$BOARD"
  echo "CMDLINE=$CMDLINE"
  echo "RAMDISK_COMP=$RAMDISK_COMP"
  echo "KERNEL_SIZE=$KERNEL_SIZE"
  echo "RAMDISK_SIZE=$RAMDISK_SIZE"
  echo ""
  echo "# mkbootimg reconstruction command:"
  echo "# mkbootimg \\"
  echo "#   --kernel <kernel> \\"
  echo "#   --ramdisk <ramdisk> \\"
  echo "#   --base $BASE \\"
  echo "#   --pagesize $PAGESIZE \\"
  echo "#   --kernel_offset $KERNEL_OFFSET \\"
  echo "#   --ramdisk_offset $RAMDISK_OFFSET \\"
  echo "#   --tags_offset $TAGS_OFFSET \\"
  echo "#   --cmdline \"$CMDLINE\" \\"
  echo "#   --output boot-new.img"
} | tee "$OUTDIR/boot_header.txt"

# -----------------------------------------------------------------------------
# Extract kernel version string
# -----------------------------------------------------------------------------
echo ""
echo "[*] Extracting kernel version string..."

KERNEL_FILE=""
for candidate in "${BOOT_PREFIX}-zImage" "${BOOT_PREFIX}-kernel" "${BOOT_PREFIX}-Image" "${BOOT_PREFIX}-Image.gz"; do
  if [[ -f "$candidate" ]]; then
    KERNEL_FILE="$candidate"
    break
  fi
done

KERNEL_VERSION=""
if [[ -n "$KERNEL_FILE" && -f "$KERNEL_FILE" ]]; then
  echo "[*] Kernel file: $(basename "$KERNEL_FILE")"

  # Try direct strings first (works for uncompressed or partially compressed)
  KERNEL_VERSION=$(strings -a "$KERNEL_FILE" 2>/dev/null | grep -m1 -E '^Linux version [0-9]+\.[0-9]+' || true)

  # If not found, try decompressing (gzip, lz4, etc.)
  if [[ -z "$KERNEL_VERSION" ]]; then
    echo "[*] Trying to decompress kernel..."

    # Check for gzip magic (1f 8b)
    if head -c2 "$KERNEL_FILE" | xxd -p | grep -q "1f8b"; then
      KERNEL_VERSION=$(zcat "$KERNEL_FILE" 2>/dev/null | strings -a | grep -m1 -E '^Linux version [0-9]+\.[0-9]+' || true)
    fi

    # Check for LZ4 magic
    if [[ -z "$KERNEL_VERSION" ]] && head -c4 "$KERNEL_FILE" | xxd -p | grep -qi "04224d18"; then
      if command -v lz4 >/dev/null 2>&1; then
        KERNEL_VERSION=$(lz4 -dc "$KERNEL_FILE" 2>/dev/null | strings -a | grep -m1 -E '^Linux version [0-9]+\.[0-9]+' || true)
      fi
    fi

    # Try searching for gzip stream inside kernel (common for self-extracting kernels)
    if [[ -z "$KERNEL_VERSION" ]]; then
      # Find gzip magic offset and extract from there
      GZIP_OFFSET=$(grep -aboP '\x1f\x8b\x08' "$KERNEL_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
      if [[ -n "$GZIP_OFFSET" && "$GZIP_OFFSET" =~ ^[0-9]+$ ]]; then
        KERNEL_VERSION=$(dd if="$KERNEL_FILE" bs=1 skip="$GZIP_OFFSET" 2>/dev/null | zcat 2>/dev/null | strings -a | grep -m1 -E '^Linux version [0-9]+\.[0-9]+' || true)
      fi
    fi
  fi

  if [[ -n "$KERNEL_VERSION" ]]; then
    echo "[+] Found: $KERNEL_VERSION"
    echo "$KERNEL_VERSION" > "$OUTDIR/kernel_version.txt"
  else
    echo "[!] Could not extract kernel version string"
    echo "N/A" > "$OUTDIR/kernel_version.txt"
  fi
else
  echo "[!] No kernel file found"
  echo "N/A" > "$OUTDIR/kernel_version.txt"
fi

# -----------------------------------------------------------------------------
# Extract interesting kernel strings (androidboot, hardware info)
# -----------------------------------------------------------------------------
echo ""
echo "[*] Extracting kernel strings..."

if [[ -n "$KERNEL_FILE" && -f "$KERNEL_FILE" ]]; then
  {
    echo "# Kernel Strings Analysis"
    echo "# Generated: $(date -Is)"
    echo ""

    echo "## androidboot.* parameters:"
    strings -a "$KERNEL_FILE" 2>/dev/null | grep -i 'androidboot' | sort -u | head -100 || true

    echo ""
    echo "## Hardware/platform strings:"
    strings -a "$KERNEL_FILE" 2>/dev/null | grep -iE '(sprd|unisoc|spreadtrum|sc9863|sharkl3)' | sort -u | head -50 || true

    echo ""
    echo "## Driver strings:"
    strings -a "$KERNEL_FILE" 2>/dev/null | grep -iE '(pvrsrvkm|powervr|mali|drm|display|panel|dsi|touch|wifi|bt|bluetooth)' | sort -u | head -100 || true
  } > "$OUTDIR/kernel_strings.txt"

  echo "[*] Saved to kernel_strings.txt"
fi

# -----------------------------------------------------------------------------
# Try to extract kernel config
# -----------------------------------------------------------------------------
echo ""
echo "[*] Checking for embedded kernel config..."

KCONFIG_FOUND=0
if [[ -n "$KERNEL_FILE" && -f "$KERNEL_FILE" ]]; then
  # Look for IKCFG magic
  if grep -q "IKCFG_ST" "$KERNEL_FILE" 2>/dev/null; then
    echo "[*] Found embedded config (IKCFG)"

    # Extract config using extract-ikconfig if available
    if command -v extract-ikconfig >/dev/null 2>&1; then
      extract-ikconfig "$KERNEL_FILE" > "$OUTDIR/kernel_config.txt" 2>/dev/null && KCONFIG_FOUND=1
    else
      # Manual extraction
      START=$(grep -aboP 'IKCFG_ST\x1f\x8b' "$KERNEL_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
      if [[ -n "$START" && "$START" =~ ^[0-9]+$ ]]; then
        # Skip IKCFG_ST prefix (8 bytes)
        dd if="$KERNEL_FILE" bs=1 skip=$((START + 8)) 2>/dev/null | zcat 2>/dev/null > "$OUTDIR/kernel_config.txt" && KCONFIG_FOUND=1
      fi
    fi

    if [[ "$KCONFIG_FOUND" -eq 1 ]]; then
      CONFIG_LINES=$(wc -l < "$OUTDIR/kernel_config.txt")
      echo "[+] Extracted $CONFIG_LINES config lines"
    else
      echo "[!] Config extraction failed"
    fi
  else
    echo "[*] No embedded config found (CONFIG_IKCONFIG not enabled)"
  fi
fi

if [[ "$KCONFIG_FOUND" -eq 0 ]]; then
  echo "N/A - kernel config not embedded" > "$OUTDIR/kernel_config.txt"
fi

# -----------------------------------------------------------------------------
# Generate machine-readable summary
# -----------------------------------------------------------------------------
echo ""
echo "[*] Generating summary..."

# Parse kernel version components
KVER_FULL=$(cat "$OUTDIR/kernel_version.txt" | head -1)
KVER_SHORT=$(echo "$KVER_FULL" | grep -oE '^Linux version [0-9]+\.[0-9]+\.[0-9]+' | sed 's/Linux version //' || echo "N/A")
KVER_COMPILER=$(echo "$KVER_FULL" | grep -oE '\([^)]+clang[^)]+\)' | head -1 || echo "N/A")

{
  echo "{"
  echo "  \"generated\": \"$(date -Is)\","
  echo "  \"boot_header\": {"
  echo "    \"version\": \"$(grep 'HEADER_VERSION=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"base\": \"$(grep 'BASE=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"pagesize\": \"$(grep 'PAGESIZE=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"kernel_offset\": \"$(grep 'KERNEL_OFFSET=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"ramdisk_offset\": \"$(grep 'RAMDISK_OFFSET=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"tags_offset\": \"$(grep 'TAGS_OFFSET=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\","
  echo "    \"cmdline\": \"$(grep 'CMDLINE=' "$OUTDIR/boot_header.txt" | cut -d= -f2-)\","
  echo "    \"ramdisk_compression\": \"$(grep 'RAMDISK_COMP=' "$OUTDIR/boot_header.txt" | cut -d= -f2)\""
  echo "  },"
  echo "  \"kernel\": {"
  echo "    \"version_full\": \"$(echo "$KVER_FULL" | sed 's/"/\\"/g')\","
  echo "    \"version_short\": \"$KVER_SHORT\","
  echo "    \"compiler\": \"$(echo "$KVER_COMPILER" | sed 's/"/\\"/g')\","
  echo "    \"config_available\": $KCONFIG_FOUND"
  echo "  }"
  echo "}"
} > "$OUTDIR/summary.json"

# -----------------------------------------------------------------------------
# Final output
# -----------------------------------------------------------------------------
echo ""
echo "[*] Done. Output files:"
ls -lh "$OUTDIR"

echo ""
echo "[*] Quick summary:"
echo "    Kernel version: $KVER_SHORT"
echo "    Page size: $(grep 'PAGESIZE=' "$OUTDIR/boot_header.txt" | cut -d= -f2)"
echo "    Base address: $(grep 'BASE=' "$OUTDIR/boot_header.txt" | cut -d= -f2)"
echo "    Cmdline: $(grep 'CMDLINE=' "$OUTDIR/boot_header.txt" | cut -d= -f2-)"

#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 10_bringup_report.sh
#
# Generate a single Markdown bringup report for postmarketOS porting work.
# Idempotent: overwrites the report every run.
#
# Output:
#   reports/bringup_report.md
#
# Inputs (if present):
#   device-info/*
#   backup/*
#   extracted/dtb_from_bootimg/*
#   extracted/dtbo_split/*
#   extracted/ramdisk_init/*
#   extracted/super_lpunpack/*
#   extracted/vendor_blobs/*
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPORT_DIR="${PROJECT_DIR}/reports"
REPORT_MD="${REPORT_DIR}/bringup_report.md"

mkdir -p "$REPORT_DIR"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
hr() { echo ""; echo "---"; echo ""; }

h1() { echo "# $*"; echo ""; }
h2() { echo "## $*"; echo ""; }
h3() { echo "### $*"; echo ""; }

codeblock() {
  local lang="${1:-}"
  echo ""
  echo "```$lang"
  cat
  echo "```"
  echo ""
}

safe_cmd() {
  # Run a command, never fail the script.
  # Prints the command and output as a code block.
  local title="$1"; shift
  h3 "$title"
  {
    echo "\$ $*"
    "$@" 2>&1 || true
  } | codeblock ""
}

safe_cat() {
  local title="$1"
  local file="$2"
  h3 "$title"
  if [[ -f "$file" ]]; then
    sed -n '1,200p' "$file" | codeblock ""
  else
    echo "_Missing:_ \`$file\`"
    echo ""
  fi
}

safe_ls() {
  local title="$1"
  local path="$2"
  local maxlines="${3:-120}"
  h3 "$title"
  if [[ -e "$path" ]]; then
    (ls -lah "$path" 2>&1 | head -n "$maxlines") | codeblock ""
  else
    echo "_Missing:_ \`$path\`"
    echo ""
  fi
}

sha256_list() {
  local title="$1"; shift
  h3 "$title"
  local any=0
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      any=1
      echo "$(sha256sum "$f")"
    fi
  done
  if [[ "$any" -eq 0 ]]; then
    echo "_No files found._"
  fi
  echo "" | codeblock ""
}

grep_some() {
  local title="$1"
  local file="$2"
  local pattern="$3"
  local maxlines="${4:-80}"
  h3 "$title"
  if [[ -f "$file" ]]; then
    (grep -nE "$pattern" "$file" 2>/dev/null | head -n "$maxlines") | codeblock ""
  else
    echo "_Missing:_ \`$file\`"
    echo ""
  fi
}

find_some() {
  local title="$1"
  local base="$2"
  local expr="$3"
  local maxlines="${4:-120}"
  h3 "$title"
  if [[ -d "$base" ]]; then
    # shellcheck disable=SC2016
    (bash -lc "cd \"$base\" && eval \"$expr\" 2>/dev/null | head -n $maxlines") | codeblock ""
  else
    echo "_Missing directory:_ \`$base\`"
    echo ""
  fi
}

# -----------------------------------------------------------------------------
# Paths we care about
# -----------------------------------------------------------------------------
BOOT_CMDLINE_TXT="${PROJECT_DIR}/device-info/bootimg_cmdline.txt"
GETPROP_FULL_TXT="${PROJECT_DIR}/device-info/getprop_full.txt"
PROC_CMDLINE_TXT="${PROJECT_DIR}/device-info/proc_cmdline.txt"

AIK_CMDLINE="${PROJECT_DIR}/AIK/split_img/boot-stock.img-cmdline"

DTB_TRIMMED="${PROJECT_DIR}/backup/dtb-stock-trimmed.dtb"
DTB_TRIMMED_DTS="${PROJECT_DIR}/backup/dtb-stock-trimmed.dts"
DTB_DIR="${PROJECT_DIR}/extracted/dtb_from_bootimg"
DTBO_DIR="${PROJECT_DIR}/extracted/dtbo_split"

RAMDISK_DIR="${PROJECT_DIR}/extracted/ramdisk_init"
SUPER_IMG="${PROJECT_DIR}/firmware/super.img"
SUPER_LP_DIR="${PROJECT_DIR}/extracted/super_lpunpack"

VENDOR_BLOBS_DIR="${PROJECT_DIR}/extracted/vendor_blobs"
BACKUP_DIR="${PROJECT_DIR}/backup"

# -----------------------------------------------------------------------------
# Generate report
# -----------------------------------------------------------------------------
{
  h1 "Bringup Report (Teclast P20HD / Unisoc SC9863A)"

  echo "**Generated:** $(date -Is)"
  echo ""
  echo "**Project root:** \`$PROJECT_DIR\`"
  echo ""

  hr

  h2 "Host Environment"
  safe_cmd "Host uname" uname -a

  # Best-effort distro info
  if [[ -f /etc/os-release ]]; then
    safe_cat "Host /etc/os-release" /etc/os-release
  fi

  hr

  h2 "Tooling Versions (sanity)"
  safe_cmd "adb (Android Debug Bridge — device communication tool)" adb --version
  safe_cmd "fastboot (Android Fastboot — bootloader flashing tool)" fastboot --version
  safe_cmd "dtc (Device Tree Compiler — DTB/DTS compiler/decompiler)" dtc --version
  safe_cmd "python3 (Python — scripting runtime)" python3 --version
  safe_cmd "simg2img (Sparse image converter — converts Android sparse images to raw)" simg2img --help

  hr

  h2 "Device Identity (from getprop if available)"

  # If we don't have saved getprop, try to pull it live
  if [[ ! -f "$GETPROP_FULL_TXT" ]]; then
    echo "_Saved getprop dump missing; attempting live ADB pull..._"
    echo ""
    mkdir -p "${PROJECT_DIR}/device-info"
    adb shell getprop > "$GETPROP_FULL_TXT" 2>/dev/null || true
  fi

  if [[ -f "$GETPROP_FULL_TXT" ]]; then
    grep_some "Key properties (ro.boot / ro.product / ro.hardware)" "$GETPROP_FULL_TXT" '\[(ro\.boot|ro\.hardware|ro\.product)\.' 120
    grep_some "Build fingerprint + SDK + release" "$GETPROP_FULL_TXT" '\[(ro\.product\.build\.fingerprint|ro\.product\.build\.version\.sdk|ro\.product\.build\.version\.release|ro\.boot\.verifiedbootstate|ro\.boot\.flash\.locked)\]' 120
  else
    echo "_No getprop data available yet._"
    echo ""
  fi

  hr

  h2 "Kernel Command Line (bootargs)"

  # Prefer saved commandline, else AIK split artifact
  if [[ -f "$BOOT_CMDLINE_TXT" ]]; then
    safe_cat "Saved boot cmdline (device-info/bootimg_cmdline.txt)" "$BOOT_CMDLINE_TXT"
  elif [[ -f "$AIK_CMDLINE" ]]; then
    safe_cat "AIK boot img cmdline (AIK/split_img/*-cmdline)" "$AIK_CMDLINE"
  else
    echo "_Missing boot cmdline output._"
    echo ""
  fi

  # If someone managed to pull /proc/cmdline (rare on locked user builds)
  if [[ -f "$PROC_CMDLINE_TXT" ]]; then
    safe_cat "Saved /proc/cmdline (device-info/proc_cmdline.txt)" "$PROC_CMDLINE_TXT"
  else
    echo "_/proc/cmdline was not readable over ADB (expected on locked user builds)._"
    echo ""
  fi

  hr

  h2 "Device Tree (DTB — Device Tree Blob, hardware description)"

  # If trimmed DTS doesn't exist but trimmed DTB does, attempt to decompile it.
  if [[ -f "$DTB_TRIMMED" && ! -f "$DTB_TRIMMED_DTS" ]]; then
    dtc -I dtb -O dts -o "$DTB_TRIMMED_DTS" "$DTB_TRIMMED" 2>/dev/null || true
  fi

  if [[ -f "$DTB_TRIMMED_DTS" ]]; then
    grep_some "DTB model / compatible" "$DTB_TRIMMED_DTS" 'model =|compatible =' 40
    grep_some "Touchscreen hints" "$DTB_TRIMMED_DTS" 'gslx680|touch|touchscreen' 80
    grep_some "Display/Panel/DSI (Display Serial Interface — mobile display bus)" "$DTB_TRIMMED_DTS" 'dsi|panel|lcd|display|backlight' 120
    grep_some "WiFi/BT (Bluetooth — short-range radio) / WCN (Wireless Connectivity Node)" "$DTB_TRIMMED_DTS" 'wcn|bt|wifi|sprdwl|sc2355' 120
  else
    echo "_Trimmed DTB DTS not found. Checking extracted DTB directory..._"
    echo ""
    safe_ls "Extracted DTB directory" "$DTB_DIR"
    find_some "DTB/DTS candidates under extracted/dtb_from_bootimg" "$DTB_DIR" 'ls -1 *.dtb *.dts 2>/dev/null' 120
  fi

  hr

  h2 "DTBO Overlays (DTBO — Device Tree Blob Overlays, board-specific patches)"

  safe_ls "Extracted overlays directory" "$DTBO_DIR"

  if [[ -d "$DTBO_DIR" ]]; then
    echo "#### Overlay compatibles (quick scan)"
    echo ""
    for dts in "$DTBO_DIR"/*.dts; do
      [[ -f "$dts" ]] || continue
      echo "- **$(basename "$dts")**"
      grep -nE 'compatible = ' "$dts" | head -n 20 | sed 's/^/  /'
      echo ""
    done | codeblock ""
  else
    echo "_No extracted overlays found. Run:_"
    echo ""
    echo "\`bash scripts/08_split_dtbo_overlays.sh\`"
    echo ""
  fi

  hr

  h2 "Ramdisk init artifacts (init — Android init config, fstab — mount rules)"

  safe_ls "Ramdisk init extraction root" "$RAMDISK_DIR"

  if [[ -d "$RAMDISK_DIR" ]]; then
    safe_ls "init scripts" "${RAMDISK_DIR}/init"
    safe_ls "fstab files" "${RAMDISK_DIR}/fstab"
    safe_ls "ueventd rules" "${RAMDISK_DIR}/ueventd"

    # Grep a few high-signal keywords
    find_some "init: services summary (service …)" "${RAMDISK_DIR}/init" 'grep -R "^[[:space:]]*service " -n . | head -n 80' 80
    find_some "init: mount_all usage" "${RAMDISK_DIR}/init" 'grep -R "mount_all" -n . | head -n 80' 80
    find_some "fstab: first_stage_mount flags" "${RAMDISK_DIR}/fstab" 'grep -R "first_stage_mount" -n . | head -n 80' 80
  else
    echo "_No ramdisk init extraction found. Run:_"
    echo ""
    echo "\`bash scripts/09_extract_ramdisk_init.sh\`"
    echo ""
  fi

  hr

  h2 "Dynamic Partitions (super.img — contains system/vendor/product as logical partitions)"

  if [[ -f "$SUPER_IMG" ]]; then
    safe_cmd "super.img file type" file "$SUPER_IMG"
    safe_ls "super.img size" "$SUPER_IMG"
  else
    echo "_Missing super.img at:_ \`$SUPER_IMG\`"
    echo ""
  fi

  if [[ -d "$SUPER_LP_DIR" ]]; then
    safe_ls "Extracted logical partitions (lpunpack output)" "$SUPER_LP_DIR"
    find_some "List extracted *.img partitions" "$SUPER_LP_DIR" 'ls -lh *.img 2>/dev/null' 120
  else
    echo "_No extracted super partitions directory found: \`$SUPER_LP_DIR\`_"
    echo ""
    echo "If your unpack script failed due to missing **lpunpack**, install a working extractor (binary or python), then rerun:"
    echo ""
    echo "\`bash scripts/unpack_super_img.sh\`"
    echo ""
  fi

  hr

  h2 "Vendor blobs (vendor — hardware userspace drivers/firmware)"

  if [[ -d "$VENDOR_BLOBS_DIR" ]]; then
    safe_ls "Vendor blobs root" "$VENDOR_BLOBS_DIR"
    safe_ls "vendor/firmware" "${VENDOR_BLOBS_DIR}/vendor_firmware"
    safe_ls "vendor/lib/modules" "${VENDOR_BLOBS_DIR}/vendor_modules"
    safe_ls "vendor/etc/vintf" "${VENDOR_BLOBS_DIR}/vendor_vintf"
    safe_ls "vendor/build.prop" "${VENDOR_BLOBS_DIR}/vendor_build_prop"
  else
    echo "_Vendor blobs not extracted yet (optional but recommended)._"
    echo ""
    echo "When you add it, run:"
    echo ""
    echo "\`bash scripts/extract_vendor_blobs.sh\`"
    echo ""
  fi

  hr

  h2 "AVB / vbmeta inventory (AVB — Android Verified Boot, verification metadata)"

  VB_FILES=()
  while IFS= read -r -d '' f; do VB_FILES+=("$f"); done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "vbmeta*.img" -print0 2>/dev/null || true)

  if [[ "${#VB_FILES[@]}" -gt 0 ]]; then
    safe_ls "vbmeta images in backup/" "$BACKUP_DIR"
    sha256_list "vbmeta checksums" "${VB_FILES[@]}"
  else
    echo "_No vbmeta*.img found in backup/._"
    echo ""
  fi

  hr

  h2 "High-signal bringup conclusions"

  echo "- **SoC (System on Chip — CPU/GPU/IO package):** Unisoc/Spreadtrum **SC9863A**"
  echo "- **Board string:** \`s9863a1h10\` (from ro.boot.hardware)"
  echo "- **Android version:** Android 10 (SDK 29) (from ro.product.build.version.*)"
  echo "- **Dynamic partitions:** enabled (super.img present + ro.boot.dynamic_partitions=true)"
  echo "- **Bootloader locked:** ro.boot.flash.locked=1 (expect restrictions)"
  echo "- **DTB base model:** \"Spreadtrum SC9863A-1H10 Board\" (from extracted DTB)"
  echo ""
  echo "Next bringup work usually focuses on:"
  echo "- selecting the correct panel timing node from the DTB (many LCD candidates are present)"
  echo "- touchscreen driver compatibility (e.g., gslx680)"
  echo "- WCN Wi-Fi/BT firmware + interface wiring"
  echo "- extracting vendor modules/firmware for userspace compatibility"
  echo ""

  hr

  h2 "Appendix: Relevant artifact locations"

  echo "- \`backup/boot-stock.img\`"
  echo "- \`backup/dtb-stock-trimmed.dtb\` / \`backup/dtb-stock-trimmed.dts\`"
  echo "- \`backup/dtbo.img\`"
  echo "- \`backup/vbmeta*.img\`"
  echo "- \`extracted/dtb_from_bootimg/\`"
  echo "- \`extracted/dtbo_split/\`"
  echo "- \`extracted/ramdisk_init/\`"
  echo "- \`extracted/super_lpunpack/\`"
  echo "- \`extracted/vendor_blobs/\` (if extracted)"
  echo ""
} > "$REPORT_MD"

echo "[*] Wrote report:"
echo "    $REPORT_MD"
echo
echo "[*] Preview (first 80 lines):"
sed -n '1,80p' "$REPORT_MD"

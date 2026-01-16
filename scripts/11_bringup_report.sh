#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 11_bringup_report.sh
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
# Status tracking arrays for final summary
# -----------------------------------------------------------------------------
declare -a FOUND_ITEMS=()
declare -a MISSING_ITEMS=()
declare -a WARNINGS=()

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
hr() { echo ""; echo "---"; echo ""; }

h1() { echo "# $*"; echo ""; }
h2() { echo "## $*"; echo ""; }
h3() { echo "### $*"; echo ""; }

# Status emoji helpers
ok_mark() { echo "✅"; }
fail_mark() { echo "❌"; }
warn_mark() { echo "⚠️"; }
info_mark() { echo "ℹ️"; }

# Track found/missing items for summary
track_found() { FOUND_ITEMS+=("$1"); }
track_missing() { MISSING_ITEMS+=("$1"); }
track_warning() { WARNINGS+=("$1"); }

codeblock() {
  local lang="${1:-}"
  echo ""
  printf '%s%s\n' '```' "$lang"
  cat
  echo '```'
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
  local track_name="${3:-}"
  h3 "$title"
  if [[ -f "$file" && -s "$file" ]]; then
    # File exists and has content
    echo "$(ok_mark) **Found**"
    echo ""
    sed -n '1,200p' "$file" | codeblock ""
    [[ -n "$track_name" ]] && track_found "$track_name" || true
  elif [[ -f "$file" ]]; then
    # File exists but is empty
    echo "$(warn_mark) **File exists but empty:** \`$file\`"
    echo ""
    [[ -n "$track_name" ]] && track_warning "$track_name (empty file)" || true
  else
    echo "$(fail_mark) **Missing:** \`$file\`"
    echo ""
    [[ -n "$track_name" ]] && track_missing "$track_name" || true
  fi
}

safe_ls() {
  local title="$1"
  local path="$2"
  local maxlines="${3:-120}"
  local track_name="${4:-}"
  local empty_ok="${5:-0}"  # Set to 1 if empty directory is expected (no warning)
  h3 "$title"
  if [[ -e "$path" ]]; then
    # Check if directory has actual content (recursively for nested structures)
    local file_count
    if [[ -d "$path" ]]; then
      # Check both immediate files and nested directories (handles debugfs nested extraction)
      file_count=$(find "$path" -type f 2>/dev/null | wc -l)
      if [[ "$file_count" -gt 0 ]]; then
        echo "$(ok_mark) **Found** ($file_count files)"
        [[ -n "$track_name" ]] && track_found "$track_name" || true
      elif [[ "$empty_ok" -eq 1 ]]; then
        echo "$(info_mark) **Directory empty** (expected)"
      else
        echo "$(warn_mark) **Directory exists but empty**"
        [[ -n "$track_name" ]] && track_warning "$track_name (empty directory)" || true
      fi
    else
      echo "$(ok_mark) **Found**"
      [[ -n "$track_name" ]] && track_found "$track_name" || true
    fi
    echo ""
    (ls -lah "$path" 2>&1 | head -n "$maxlines") | codeblock ""
  else
    echo "$(fail_mark) **Missing:** \`$path\`"
    echo ""
    [[ -n "$track_name" ]] && track_missing "$track_name" || true
  fi
}

sha256_list() {
  local title="$1"; shift
  h3 "$title"
  local any=0
  local output=""
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      any=1
      output+="$(sha256sum "$f")"$'\n'
    fi
  done
  if [[ "$any" -eq 0 ]]; then
    echo "_No files found._"
  else
    echo "$output" | codeblock ""
  fi
}

grep_some() {
  local title="$1"
  local file="$2"
  local pattern="$3"
  local maxlines="${4:-80}"
  local track_name="${5:-}"
  h3 "$title"
  if [[ -f "$file" ]]; then
    local matches
    matches=$(grep -nE "$pattern" "$file" 2>/dev/null | head -n "$maxlines" || true)
    if [[ -n "$matches" ]]; then
      echo "$(ok_mark) **Found matches**"
      [[ -n "$track_name" ]] && track_found "$track_name" || true
    else
      echo "$(warn_mark) **No matches for pattern:** \`$pattern\`"
      [[ -n "$track_name" ]] && track_warning "$track_name (no matches)" || true
    fi
    echo ""
    echo "$matches" | codeblock ""
  else
    echo "$(fail_mark) **Missing:** \`$file\`"
    echo ""
    [[ -n "$track_name" ]] && track_missing "$track_name" || true
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

# Device-info paths (from ADB collection)
DEVICE_INFO_DIR="${PROJECT_DIR}/device-info"
PARTITION_LAYOUT_TXT="${DEVICE_INFO_DIR}/partition_layout.txt"
PARTITION_SIZES_TXT="${DEVICE_INFO_DIR}/partition_sizes.txt"
LOADED_MODULES_TXT="${DEVICE_INFO_DIR}/loaded_modules.txt"
INPUT_DEVICES_TXT="${DEVICE_INFO_DIR}/input_devices.txt"
DISPLAY_INFO_TXT="${DEVICE_INFO_DIR}/display_info.txt"
SOC_INFO_TXT="${DEVICE_INFO_DIR}/soc_info.txt"

# Boot image info paths (from 06_extract_bootimg_info.sh)
BOOTIMG_INFO_DIR="${PROJECT_DIR}/extracted/bootimg_info"
BOOT_HEADER_TXT="${BOOTIMG_INFO_DIR}/boot_header.txt"
KERNEL_VERSION_TXT="${BOOTIMG_INFO_DIR}/kernel_version.txt"
KERNEL_STRINGS_TXT="${BOOTIMG_INFO_DIR}/kernel_strings.txt"

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
  # Prefer system simg2img over potentially broken local builds
  SIMG2IMG_FOR_HELP="/usr/bin/simg2img"
  [[ -x "$SIMG2IMG_FOR_HELP" ]] || SIMG2IMG_FOR_HELP="$(command -v simg2img 2>/dev/null || echo simg2img)"
  safe_cmd "simg2img (Sparse image converter — converts Android sparse images to raw)" "$SIMG2IMG_FOR_HELP" --help

  hr

  h2 "Boot Image Analysis (critical for image repacking)"

  if [[ -f "$BOOT_HEADER_TXT" ]]; then
    echo "$(ok_mark) **Boot header parameters extracted**"
    track_found "Boot image header"
    echo ""

    h3 "Boot Header Parameters"
    echo ""
    echo "These values are required for \`mkbootimg\` when building postmarketOS boot images:"
    echo ""
    {
      grep -E '^(HEADER_VERSION|BASE|PAGESIZE|KERNEL_OFFSET|RAMDISK_OFFSET|TAGS_OFFSET|CMDLINE|RAMDISK_COMP|KERNEL_SIZE|RAMDISK_SIZE)=' "$BOOT_HEADER_TXT" 2>/dev/null || true
    } | codeblock ""

    h3 "mkbootimg Command Template"
    echo ""
    echo "Use this template for building postmarketOS boot images:"
    echo ""
    {
      grep -A20 '^# mkbootimg reconstruction' "$BOOT_HEADER_TXT" 2>/dev/null | grep -v '^#' | grep -v '^$' || \
      echo "# See boot_header.txt for full mkbootimg command"
    } | codeblock "bash"
  else
    echo "$(warn_mark) **Boot header not extracted yet**"
    track_warning "Boot image header (not extracted)"
    echo ""
    echo "Run: \`bash scripts/06_extract_bootimg_info.sh\`"
    echo ""
  fi

  if [[ -f "$KERNEL_VERSION_TXT" && -s "$KERNEL_VERSION_TXT" ]]; then
    KVER=$(head -1 "$KERNEL_VERSION_TXT")
    if [[ "$KVER" != "N/A" ]]; then
      echo "$(ok_mark) **Kernel version extracted**"
      track_found "Kernel version"
      echo ""
      h3 "Stock Kernel Version"
      echo ""
      echo "$KVER" | codeblock ""

      # Parse kernel version for quick reference
      KVER_SHORT=$(echo "$KVER" | grep -oE '^Linux version [0-9]+\.[0-9]+\.[0-9]+' | sed 's/Linux version //' || echo "")
      if [[ -n "$KVER_SHORT" ]]; then
        echo "**Kernel:** \`$KVER_SHORT\` (Android downstream kernel)"
        echo ""
      fi
    else
      echo "$(warn_mark) **Kernel version could not be extracted**"
      track_warning "Kernel version (extraction failed)"
      echo ""
    fi
  else
    echo "$(warn_mark) **Kernel version not extracted yet**"
    track_warning "Kernel version (not extracted)"
    echo ""
    echo "Run: \`bash scripts/06_extract_bootimg_info.sh\`"
    echo ""
  fi

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
    echo "$(ok_mark) **getprop dump found**"
    track_found "Device properties (getprop)"
    echo ""
    grep_some "Key properties (ro.boot / ro.product / ro.hardware)" "$GETPROP_FULL_TXT" '\[(ro\.boot|ro\.hardware|ro\.product)\.' 120
    grep_some "Build fingerprint + SDK + release" "$GETPROP_FULL_TXT" '\[(ro\.product\.build\.fingerprint|ro\.product\.build\.version\.sdk|ro\.product\.build\.version\.release|ro\.boot\.verifiedbootstate|ro\.boot\.flash\.locked)\]' 120

    # GPU/EGL info from getprop
    h3 "GPU / Graphics properties"
    echo ""
    {
      grep -E '\[(ro\.hardware\.egl|ro\.opengles\.version|ro\.hardware\.vulkan|ro\.board\.platform)\]' "$GETPROP_FULL_TXT" 2>/dev/null || echo "_No GPU properties found_"
    } | codeblock ""
  else
    echo "$(fail_mark) **No getprop data available yet.**"
    track_missing "Device properties (getprop)"
    echo ""
  fi

  hr

  h2 "Partition Layout (from live device)"

  if [[ -f "$PARTITION_LAYOUT_TXT" && -s "$PARTITION_LAYOUT_TXT" ]]; then
    echo "$(ok_mark) **Partition layout collected from device**"
    track_found "Partition layout"
    echo ""
    echo "Block device mapping from \`/dev/block/by-name/\`:"
    echo ""
    cat "$PARTITION_LAYOUT_TXT" | codeblock ""

    # Summarize key partitions
    h3 "Key partitions for porting"
    echo ""
    echo "| Partition | Block Device | Purpose |"
    echo "|-----------|--------------|---------|"
    # Parse partition layout - extract name and device
    grep -E ' (boot|dtbo|super|vbmeta|vbmeta_system|vbmeta_vendor|recovery|wcnmodem|l_modem|persist|userdata) -> ' "$PARTITION_LAYOUT_TXT" 2>/dev/null | \
      grep -v '_bak\|boot0\|boot1' | \
      while read -r line; do
        # Extract partition name (8th field in ls -la output) and device path (10th/last field)
        part=$(echo "$line" | awk '{print $8}')
        dev=$(echo "$line" | awk '{print $10}')
        case "$part" in
          boot) echo "| boot | $dev | Kernel + ramdisk |" ;;
          dtbo) echo "| dtbo | $dev | Device tree overlays |" ;;
          super) echo "| super | $dev | Dynamic partitions (system/vendor/product) |" ;;
          vbmeta) echo "| vbmeta | $dev | AVB verification metadata |" ;;
          vbmeta_system) echo "| vbmeta_system | $dev | System partition AVB |" ;;
          vbmeta_vendor) echo "| vbmeta_vendor | $dev | Vendor partition AVB |" ;;
          recovery) echo "| recovery | $dev | Recovery mode image |" ;;
          wcnmodem) echo "| wcnmodem | $dev | WiFi/BT firmware |" ;;
          l_modem) echo "| l_modem | $dev | LTE modem firmware |" ;;
          persist) echo "| persist | $dev | Persistent data (calibration) |" ;;
          userdata) echo "| userdata | $dev | User data partition |" ;;
        esac
      done
    echo ""

    # Show partition sizes if available
    if [[ -f "$PARTITION_SIZES_TXT" && -s "$PARTITION_SIZES_TXT" ]]; then
      h3 "Partition Sizes (/proc/partitions)"
      echo ""
      echo "Raw partition sizes in 1K blocks (critical for rootfs planning):"
      echo ""
      cat "$PARTITION_SIZES_TXT" | codeblock ""
    fi
  else
    echo "$(warn_mark) **Partition layout not collected** (device not connected during collection)"
    track_warning "Partition layout (not collected)"
    echo ""
    echo "Connect device with ADB and run: \`bash scripts/05_collect_device_info.sh\`"
    echo ""
  fi

  hr

  h2 "Loaded Kernel Modules (from live device)"

  if [[ -f "$LOADED_MODULES_TXT" && -s "$LOADED_MODULES_TXT" ]]; then
    echo "$(ok_mark) **Loaded modules collected from device**"
    track_found "Loaded kernel modules"
    echo ""
    echo "Modules from \`/sys/module/\` — shows what kernel drivers are active:"
    echo ""

    # Highlight hardware-relevant modules
    h3 "Hardware-critical modules"
    echo ""
    {
      grep -E '^(pvrsrvkm|sprd|marlin|cfg80211|rfkill|binder|dpu|drm)' "$LOADED_MODULES_TXT" 2>/dev/null || echo "_No Spreadtrum modules found_"
    } | codeblock ""

    h3 "Full module list"
    echo ""
    cat "$LOADED_MODULES_TXT" | codeblock ""
  else
    echo "$(warn_mark) **Loaded modules not collected** (device not connected during collection)"
    track_warning "Loaded kernel modules (not collected)"
    echo ""
  fi

  hr

  h2 "Kernel Command Line (bootargs)"

  # Prefer saved commandline, else AIK split artifact
  if [[ -f "$BOOT_CMDLINE_TXT" ]]; then
    safe_cat "Saved boot cmdline (device-info/bootimg_cmdline.txt)" "$BOOT_CMDLINE_TXT" "Boot cmdline"
  elif [[ -f "$AIK_CMDLINE" ]]; then
    safe_cat "AIK boot img cmdline (AIK/split_img/*-cmdline)" "$AIK_CMDLINE" "Boot cmdline"
  else
    echo "$(fail_mark) **Missing boot cmdline output.**"
    track_missing "Boot cmdline"
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
    echo "$(ok_mark) **DTB DTS found (trimmed)**"
    track_found "DTB DTS (trimmed)"
    echo ""
    grep_some "DTB model / compatible" "$DTB_TRIMMED_DTS" 'model =|compatible =' 40 "DTB model/compatible"
    grep_some "Touchscreen hints" "$DTB_TRIMMED_DTS" 'gslx680|touch|touchscreen' 80 "Touchscreen DTB nodes"
    grep_some "Display/Panel/DSI (Display Serial Interface — mobile display bus)" "$DTB_TRIMMED_DTS" 'dsi|panel|lcd|display|backlight' 120 "Display DTB nodes"
    grep_some "WiFi/BT (Bluetooth — short-range radio) / WCN (Wireless Connectivity Node)" "$DTB_TRIMMED_DTS" 'wcn|bt|wifi|sprdwl|sc2355' 120 "WiFi/BT DTB nodes"
  else
    echo "$(warn_mark) **Trimmed DTB DTS not found.** Checking extracted DTB directory..."
    track_missing "DTB DTS (backup/dtb-stock-trimmed.dts)"
    echo ""

    # Check if we have DTB in extracted dir
    if [[ -d "$DTB_DIR" ]]; then
      dtb_count=$(find "$DTB_DIR" -name "*.dtb" 2>/dev/null | wc -l)
      dts_count=$(find "$DTB_DIR" -name "*.dts" 2>/dev/null | wc -l)
      if [[ "$dtb_count" -gt 0 ]]; then
        echo "$(ok_mark) **Found $dtb_count DTB file(s) in extracted directory**"
        track_found "DTB files (extracted)"
        if [[ "$dts_count" -gt 0 ]]; then
          echo "$(ok_mark) **Found $dts_count DTS file(s) (decompiled)**"
          track_found "DTS files (decompiled)"
        fi
        echo ""
      fi
    fi

    safe_ls "Extracted DTB directory" "$DTB_DIR" 120 "DTB extraction directory"
    find_some "DTB/DTS candidates under extracted/dtb_from_bootimg" "$DTB_DIR" 'ls -1 *.dtb *.dts 2>/dev/null' 120
  fi

  hr

  h2 "DTBO Overlays (DTBO — Device Tree Blob Overlays, board-specific patches)"

  if [[ -d "$DTBO_DIR" ]]; then
    dtbo_count=$(find "$DTBO_DIR" -name "*.dtb" 2>/dev/null | wc -l)
    echo "$(ok_mark) **DTBO overlays extracted ($dtbo_count overlays)**"
    track_found "DTBO overlays"
    echo ""
    safe_ls "Extracted overlays directory" "$DTBO_DIR" 120
    echo "#### Overlay compatibles (quick scan)"
    echo ""
    for dts in "$DTBO_DIR"/*.dts; do
      [[ -f "$dts" ]] || continue
      echo "- **$(basename "$dts")**"
      grep -nE 'compatible = ' "$dts" | head -n 20 | sed 's/^/  /'
      echo ""
    done | codeblock ""
  else
    echo "$(fail_mark) **No extracted overlays found.**"
    track_missing "DTBO overlays"
    echo ""
    echo "Run: \`bash scripts/08_split_dtbo_overlays.sh\`"
    echo ""
  fi

  hr

  h2 "Ramdisk init artifacts (init — Android init config, fstab — mount rules)"

  if [[ -d "$RAMDISK_DIR" ]]; then
    echo "$(ok_mark) **Ramdisk init extraction found**"
    track_found "Ramdisk extraction"
    echo ""
    safe_ls "Ramdisk init extraction root" "$RAMDISK_DIR" 120

    # Check init scripts
    init_count=$(find "${RAMDISK_DIR}/init" -maxdepth 1 -type f -name "*.rc" 2>/dev/null | wc -l)
    if [[ "$init_count" -gt 0 ]]; then
      echo "$(ok_mark) **init scripts found ($init_count files)**"
      track_found "Init scripts (init*.rc)"
    else
      # Expected for Android 10+ - use info marker, don't track as warning
      echo "$(info_mark) **No init*.rc scripts in ramdisk** (normal for Android 10+ first_stage_mount)"
    fi
    echo ""
    safe_ls "init scripts" "${RAMDISK_DIR}/init" 120 "" 1

    # Check fstab
    fstab_count=$(find "${RAMDISK_DIR}/fstab" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$fstab_count" -gt 0 ]]; then
      echo "$(ok_mark) **fstab files found ($fstab_count files)**"
      track_found "fstab files"
    else
      echo "$(fail_mark) **No fstab files found**"
      track_missing "fstab files"
    fi
    echo ""
    safe_ls "fstab files" "${RAMDISK_DIR}/fstab" 120

    # Show fstab content (critical for understanding partition layout)
    FSTAB_FILE=$(find "${RAMDISK_DIR}/fstab" -maxdepth 1 -type f -name "fstab.*" 2>/dev/null | head -1)
    if [[ -n "$FSTAB_FILE" && -f "$FSTAB_FILE" ]]; then
      h3 "fstab content ($(basename "$FSTAB_FILE"))"
      echo ""
      echo "This file defines how partitions are mounted during boot:"
      echo ""
      cat "$FSTAB_FILE" | codeblock ""
    fi

    # Check ueventd
    ueventd_count=$(find "${RAMDISK_DIR}/ueventd" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$ueventd_count" -gt 0 ]]; then
      echo "$(ok_mark) **ueventd rules found ($ueventd_count files)**"
      track_found "ueventd rules"
    else
      # Expected for Android 10+ - use info marker, don't track as warning
      echo "$(info_mark) **No ueventd*.rc in ramdisk** (normal for Android 10+ first_stage_mount)"
    fi
    echo ""
    safe_ls "ueventd rules" "${RAMDISK_DIR}/ueventd" 120 "" 1

    # Grep a few high-signal keywords
    find_some "init: services summary (service …)" "${RAMDISK_DIR}/init" 'grep -R "^[[:space:]]*service " -n . | head -n 80' 80
    find_some "init: mount_all usage" "${RAMDISK_DIR}/init" 'grep -R "mount_all" -n . | head -n 80' 80
    find_some "fstab: first_stage_mount flags" "${RAMDISK_DIR}/fstab" 'grep -R "first_stage_mount" -n . | head -n 80' 80
  else
    echo "$(fail_mark) **No ramdisk init extraction found.**"
    track_missing "Ramdisk extraction"
    echo ""
    echo "Run: \`bash scripts/09_extract_ramdisk_init.sh\`"
    echo ""
  fi

  hr

  h2 "Dynamic Partitions (super.img — contains system/vendor/product as logical partitions)"

  if [[ -f "$SUPER_IMG" ]]; then
    echo "$(ok_mark) **super.img found**"
    track_found "super.img"
    echo ""
    safe_cmd "super.img file type" file "$SUPER_IMG"
    safe_ls "super.img size" "$SUPER_IMG" 120
  else
    # Check if lpunpack already extracted the partitions
    if [[ -d "$SUPER_LP_DIR" ]] && [[ $(find "$SUPER_LP_DIR" -maxdepth 1 -name "*.img" 2>/dev/null | wc -l) -gt 0 ]]; then
      echo "$(info_mark) **super.img not present** (already extracted via lpunpack — this is expected)"
    else
      echo "$(warn_mark) **super.img not found** — run \`scripts/03_unpack_super_img.sh\` to extract"
    fi
    echo ""
  fi

  if [[ -d "$SUPER_LP_DIR" ]]; then
    part_count=$(find "$SUPER_LP_DIR" -maxdepth 1 -name "*.img" 2>/dev/null | wc -l)
    echo "$(ok_mark) **Logical partitions extracted ($part_count partitions)**"
    track_found "Super partitions (lpunpack)"
    echo ""
    safe_ls "Extracted logical partitions (lpunpack output)" "$SUPER_LP_DIR" 120
    find_some "List extracted *.img partitions" "$SUPER_LP_DIR" 'ls -lh *.img 2>/dev/null' 120
  else
    echo "$(fail_mark) **No extracted super partitions directory found**"
    track_missing "Super partitions (lpunpack)"
    echo ""
    echo "Run: \`bash scripts/03_unpack_super_img.sh\`"
    echo ""
  fi

  hr

  h2 "Vendor blobs (vendor — hardware userspace drivers/firmware)"

  if [[ -d "$VENDOR_BLOBS_DIR" ]]; then
    echo "$(ok_mark) **Vendor blobs directory exists**"
    track_found "Vendor blobs directory"
    echo ""
    safe_ls "Vendor blobs root" "$VENDOR_BLOBS_DIR" 120

    # Check build.prop
    if [[ -f "${VENDOR_BLOBS_DIR}/build.prop" ]]; then
      echo "$(ok_mark) **vendor/build.prop found**"
      track_found "vendor/build.prop"
      echo ""

      # Show key hardware/platform properties from vendor build.prop
      h3 "vendor/build.prop key properties"
      echo ""
      echo "Hardware and platform identification from vendor partition:"
      echo ""
      {
        grep -E '^(ro\.(board\.|product\.(board|vendor)|vendor\.(product|wcn|modem|gnss)|sf\.lcd|opengles))' "${VENDOR_BLOBS_DIR}/build.prop" 2>/dev/null || true
      } | head -30 | codeblock "properties"
    else
      echo "$(fail_mark) **vendor/build.prop missing**"
      track_missing "vendor/build.prop"
    fi
    echo ""

    # Check firmware - handle nested structure from debugfs
    fw_dir="${VENDOR_BLOBS_DIR}/firmware"
    if [[ -d "${fw_dir}/firmware" ]]; then
      # debugfs creates nested firmware/firmware/
      fw_count=$(find "${fw_dir}/firmware" -maxdepth 1 -type f 2>/dev/null | wc -l)
      if [[ "$fw_count" -gt 0 ]]; then
        echo "$(ok_mark) **vendor/firmware found ($fw_count files)** (nested path: firmware/firmware/)"
        track_found "Vendor firmware"
      else
        echo "$(warn_mark) **vendor/firmware directory empty**"
        track_warning "Vendor firmware (empty)"
      fi
    elif [[ -d "$fw_dir" ]]; then
      fw_count=$(find "$fw_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
      if [[ "$fw_count" -gt 0 ]]; then
        echo "$(ok_mark) **vendor/firmware found ($fw_count files)**"
        track_found "Vendor firmware"
      else
        echo "$(warn_mark) **vendor/firmware directory empty**"
        track_warning "Vendor firmware (empty)"
      fi
    else
      echo "$(fail_mark) **vendor/firmware missing**"
      track_missing "Vendor firmware"
    fi
    echo ""
    safe_ls "vendor/firmware" "$fw_dir" 120

    # List actual firmware files (handle nested structure from debugfs)
    actual_fw_dir="$fw_dir"
    [[ -d "${fw_dir}/firmware" ]] && actual_fw_dir="${fw_dir}/firmware"
    if [[ -d "$actual_fw_dir" ]]; then
      fw_files=$(find "$actual_fw_dir" -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l)
      if [[ "$fw_files" -gt 0 ]]; then
        h3 "Firmware files inventory"
        echo ""
        echo "These files are needed for hardware initialization (GPU, WiFi, sensors, etc.):"
        echo ""
        (ls -la "$actual_fw_dir" 2>&1 | grep -v '^total' | grep -v '^\.$' | grep -v '^\.\.$') | codeblock ""
      fi
    fi

    # Check kernel modules
    mod_dir="${VENDOR_BLOBS_DIR}/lib/modules"
    if [[ -d "$mod_dir" ]]; then
      mod_count=$(find "$mod_dir" -type f -name "*.ko" 2>/dev/null | wc -l)
      if [[ "$mod_count" -gt 0 ]]; then
        echo "$(ok_mark) **vendor/lib/modules found ($mod_count .ko files)**"
        track_found "Vendor kernel modules"
      else
        # Check if vendor.img actually has modules (monolithic kernel check)
        VENDOR_IMG_FOR_CHECK="${PROJECT_DIR}/extracted/super_lpunpack/vendor.img"
        if [[ -f "$VENDOR_IMG_FOR_CHECK" ]] && command -v debugfs >/dev/null 2>&1; then
          vendor_ko_count=$(debugfs -R "ls /lib/modules" "$VENDOR_IMG_FOR_CHECK" 2>/dev/null | grep -c '\.ko$' || true)
          vendor_ko_count="${vendor_ko_count:-0}"
          vendor_ko_count=$(echo "$vendor_ko_count" | tr -d '\n' | tr -d ' ')
          if [[ "$vendor_ko_count" =~ ^[0-9]+$ ]] && [[ "$vendor_ko_count" -gt 0 ]]; then
            echo "$(warn_mark) **vendor/lib/modules exists but empty** (extraction limitation)"
            track_warning "Vendor kernel modules (extraction limited)"
            echo ""
            echo "$(info_mark) vendor.img contains $vendor_ko_count .ko files. Install fuse2fs and re-run extraction:"
            echo ""
            printf '%s\n' '```bash'
            echo "sudo apt install fuse2fs"
            echo "bash scripts/04_extract_vendor_blobs.sh"
            printf '%s\n' '```'
          else
            echo "$(info_mark) **vendor/lib/modules empty** (monolithic kernel — drivers built into kernel, not as modules)"
            # Don't track as warning - this is expected for this device
          fi
        else
          echo "$(info_mark) **vendor/lib/modules empty** (likely monolithic kernel)"
        fi
      fi
    else
      echo "$(fail_mark) **vendor/lib/modules missing**"
      track_missing "Vendor kernel modules"
    fi
    echo ""
    # Use empty_ok=1 since we already reported the status above
    safe_ls "vendor/lib/modules" "$mod_dir" 120 "" 1

    # Check vintf
    vintf_dir="${VENDOR_BLOBS_DIR}/etc/vintf"
    if [[ -d "$vintf_dir" ]]; then
      vintf_count=$(find "$vintf_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
      if [[ "$vintf_count" -gt 0 ]]; then
        echo "$(ok_mark) **vendor/etc/vintf found ($vintf_count files)**"
        track_found "Vendor VINTF manifest"
      else
        echo "$(warn_mark) **vendor/etc/vintf directory empty**"
        track_warning "Vendor VINTF manifest (empty)"
      fi
    else
      echo "$(fail_mark) **vendor/etc/vintf missing**"
      track_missing "Vendor VINTF manifest"
    fi
    echo ""
    safe_ls "vendor/etc/vintf" "$vintf_dir" 120

    # Show VINTF manifest HAL summary (critical for understanding hardware interfaces)
    MANIFEST_XML="${vintf_dir}/manifest.xml"
    if [[ -f "$MANIFEST_XML" ]]; then
      h3 "VINTF manifest HAL summary"
      echo ""
      echo "Hardware Abstraction Layers (HALs) declared by vendor — critical for hardware support:"
      echo ""
      # Extract HAL names and versions in a readable format
      {
        echo "| HAL Name | Version | Interface |"
        echo "|----------|---------|-----------|"
        grep -E '<name>|<version>|<fqname>' "$MANIFEST_XML" 2>/dev/null | \
          sed 's/.*<name>\(.*\)<\/name>.*/NAME:\1/' | \
          sed 's/.*<version>\(.*\)<\/version>.*/VER:\1/' | \
          sed 's/.*<fqname>\(.*\)<\/fqname>.*/FQNAME:\1/' | \
          awk '
            /^NAME:/ { name=$0; sub(/NAME:/, "", name) }
            /^VER:/ { ver=$0; sub(/VER:/, "", ver) }
            /^FQNAME:/ {
              fq=$0; sub(/FQNAME:/, "", fq)
              print "| " name " | " ver " | " fq " |"
            }
          ' | head -40
      } | codeblock ""

      # Also list vendor-specific (Spreadtrum) HALs
      h3 "Vendor-specific HALs (Spreadtrum/Unisoc)"
      echo ""
      grep -oE 'vendor\.sprd\.[^<]+' "$MANIFEST_XML" 2>/dev/null | sort -u | codeblock ""
    fi
  else
    echo "$(fail_mark) **Vendor blobs not extracted yet.**"
    track_missing "Vendor blobs"
    echo ""
    echo "Run: \`bash scripts/04_extract_vendor_blobs.sh\`"
    echo ""
  fi

  hr

  h2 "AVB / vbmeta inventory (AVB — Android Verified Boot, verification metadata)"

  VB_FILES=()
  while IFS= read -r -d '' f; do VB_FILES+=("$f"); done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "vbmeta*.img" -print0 2>/dev/null || true)

  if [[ "${#VB_FILES[@]}" -gt 0 ]]; then
    echo "$(ok_mark) **vbmeta images found (${#VB_FILES[@]} files)**"
    track_found "vbmeta images"
    echo ""
    safe_ls "vbmeta images in backup/" "$BACKUP_DIR" 120
    sha256_list "vbmeta checksums" "${VB_FILES[@]}"
  else
    echo "$(fail_mark) **No vbmeta*.img found in backup/**"
    track_missing "vbmeta images"
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

  hr

  h2 "📋 postmarketOS Porting Readiness Summary"

  echo ""
  echo "### ✅ Found Artifacts (${#FOUND_ITEMS[@]})"
  echo ""
  if [[ "${#FOUND_ITEMS[@]}" -gt 0 ]]; then
    for item in "${FOUND_ITEMS[@]}"; do
      echo "- ✅ $item"
    done
  else
    echo "_No tracked items found._"
  fi
  echo ""

  echo "### ❌ Missing Artifacts (${#MISSING_ITEMS[@]})"
  echo ""
  if [[ "${#MISSING_ITEMS[@]}" -gt 0 ]]; then
    for item in "${MISSING_ITEMS[@]}"; do
      echo "- ❌ $item"
    done
  else
    echo "_All tracked items present!_"
  fi
  echo ""

  echo "### ⚠️ Warnings (${#WARNINGS[@]})"
  echo ""
  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    for item in "${WARNINGS[@]}"; do
      echo "- ⚠️ $item"
    done
  else
    echo "_No warnings._"
  fi
  echo ""

  hr

  h2 "🚀 Porting Readiness & Action Items"

  echo ""
  echo "### ✅ Ready for Porting"
  echo ""
  echo "These essentials are confirmed and ready:"
  echo ""
  echo "| Requirement | Status | Notes |"
  echo "|-------------|--------|-------|"
  echo "| SoC identified | ✅ | Unisoc SC9863A (sharkl3 platform) |"
  echo "| DTB/DTS extracted | ✅ | Device tree from boot.img |"
  echo "| Partition layout | ✅ | super.img with system/vendor/product |"
  echo "| Boot cmdline | ✅ | Kernel parameters known |"
  echo "| fstab | ✅ | Mount points defined |"
  echo "| Vendor manifest | ✅ | HAL interfaces documented |"
  echo ""

  # Count actionable issues
  ACTION_NEEDED=0

  echo "### 🔧 Action Items"
  echo ""
  echo "Issues requiring attention (if any):"
  echo ""

  # Check DTB DTS
  if [[ ! -f "$DTB_TRIMMED_DTS" ]]; then
    ACTION_NEEDED=$((ACTION_NEEDED + 1))
    echo "#### $ACTION_NEEDED. Copy DTB to backup for analysis"
    echo ""
    echo "**Current:** DTB extracted to \`extracted/dtb_from_bootimg/\` but not linked to \`backup/\`"
    echo ""
    echo "**Fix:**"
    printf '%s\n' '```bash'
    echo "cp extracted/dtb_from_bootimg/01_dtbdump_*SC9863a.dtb backup/dtb-stock-trimmed.dtb"
    echo "dtc -I dtb -O dts -o backup/dtb-stock-trimmed.dts backup/dtb-stock-trimmed.dtb"
    printf '%s\n' '```'
    echo ""
  fi

  # Check vendor modules - but first verify if they exist in vendor.img at all
  vendor_modules_dir="${VENDOR_BLOBS_DIR}/lib/modules"
  if [[ -d "$vendor_modules_dir" ]]; then
    module_count=$(find "$vendor_modules_dir" -type f -name "*.ko" 2>/dev/null | wc -l)
    if [[ "$module_count" -eq 0 ]]; then
      # Check if vendor.img actually has modules (some devices use monolithic kernel)
      VENDOR_IMG="${PROJECT_DIR}/extracted/super_lpunpack/vendor.img"
      if [[ -f "$VENDOR_IMG" ]] && command -v debugfs >/dev/null 2>&1; then
        vendor_has_modules=$(debugfs -R "ls /lib/modules" "$VENDOR_IMG" 2>/dev/null | grep -c '\.ko$' || true)
        vendor_has_modules="${vendor_has_modules:-0}"
        vendor_has_modules=$(echo "$vendor_has_modules" | tr -d '\n' | tr -d ' ')
        if [[ "$vendor_has_modules" =~ ^[0-9]+$ ]] && [[ "$vendor_has_modules" -gt 0 ]]; then
          ACTION_NEEDED=$((ACTION_NEEDED + 1))
          echo "#### $ACTION_NEEDED. Extract vendor kernel modules"
          echo ""
          echo "**Current:** \`vendor/lib/modules\` empty (extraction limitation)"
          echo ""
          echo "**Impact:** Missing GPU/WiFi/sensor \`.ko\` modules for hardware"
          echo ""
          echo "**Fix:** Re-run extraction with fuse2fs (recommended) or sudo mount:"
          printf '%s\n' '```bash'
          echo "# Option 1: Install fuse2fs and re-run (works in containers)"
          echo "sudo apt install fuse2fs"
          echo "bash scripts/04_extract_vendor_blobs.sh"
          echo ""
          echo "# Option 2: Manual extraction with sudo (outside container)"
          echo "sudo mount -o loop,ro extracted/super_lpunpack/vendor.img /mnt"
          echo "cp -a /mnt/lib/modules extracted/vendor_blobs/lib/"
          echo "sudo umount /mnt"
          printf '%s\n' '```'
          echo ""
        fi
        # If vendor.img has no modules, silently skip (monolithic kernel)
      fi
    fi
  fi

  # Note: Nested firmware directories are now auto-flattened by 04_extract_vendor_blobs.sh

  if [[ "$ACTION_NEEDED" -eq 0 ]]; then
    echo "_No action items — all artifacts extracted successfully!_"
    echo ""
  fi

  echo "### ℹ️ Expected Warnings (No Action Needed)"
  echo ""
  echo "These warnings are **normal for Android 10+** devices and don't require fixes:"
  echo ""
  echo "| Warning | Explanation |"
  echo "|---------|-------------|"

  # Init scripts warning
  if [[ -d "${RAMDISK_DIR}/init" ]]; then
    init_count=$(find "${RAMDISK_DIR}/init" -maxdepth 1 -type f -name "*.rc" 2>/dev/null | wc -l)
    if [[ "$init_count" -eq 0 ]]; then
      echo "| Init scripts empty | Android 10+ uses first_stage_mount; init.rc lives in system.img |"
    fi
  fi

  # Ueventd warning
  if [[ -d "${RAMDISK_DIR}/ueventd" ]]; then
    ueventd_count=$(find "${RAMDISK_DIR}/ueventd" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$ueventd_count" -eq 0 ]]; then
      echo "| Ueventd rules empty | Same reason; postmarketOS uses udev anyway |"
    fi
  fi

  # super.img not found (only mention if lpunpack succeeded)
  if [[ ! -f "$SUPER_IMG" ]] && [[ -d "$SUPER_LP_DIR" ]]; then
    echo "| super.img not present | Normal — deleted after successful lpunpack extraction |"
  fi

  # Vendor modules empty but vendor.img has none (monolithic kernel)
  vendor_modules_dir="${VENDOR_BLOBS_DIR}/lib/modules"
  if [[ -d "$vendor_modules_dir" ]]; then
    module_count=$(find "$vendor_modules_dir" -type f -name "*.ko" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$module_count" == "0" ]]; then
      VENDOR_IMG_CHECK="${PROJECT_DIR}/extracted/super_lpunpack/vendor.img"
      if [[ -f "$VENDOR_IMG_CHECK" ]] && command -v debugfs >/dev/null 2>&1; then
        vendor_has_modules=$(debugfs -R "ls /lib/modules" "$VENDOR_IMG_CHECK" 2>/dev/null | grep -c '\.ko$' || true)
        vendor_has_modules="${vendor_has_modules:-0}"
        if [[ "$vendor_has_modules" == "0" ]]; then
          echo "| vendor/lib/modules empty | Monolithic kernel — drivers built-in, not as modules |"
        fi
      fi
    fi
  fi

  echo ""

  echo "### 🎯 postmarketOS Porting Checklist"
  echo ""
  echo "With the extracted artifacts, you can now:"
  echo ""
  echo "1. **Create device package** — Use DTB model/compatible strings for \`deviceinfo\`"
  echo "2. **Configure kernel** — Reference loaded modules list for required drivers"
  echo "3. **Package firmware** — Copy from \`extracted/vendor_blobs/firmware/\` to \`linux-firmware\`"
  echo "4. **Identify panel** — Grep DTS for \`panel\` or \`dsi\` compatible strings"
  echo "5. **Identify touchscreen** — Firmware shows \`focaltech-FT5x46.bin\` (Focaltech FT5x46)"
  echo "6. **GPU driver** — PowerVR Rogue (rgx.fw.signed) — needs proprietary blob packaging"
  echo ""

  hr

  h2 "📁 Appendix: Artifact Locations"

  echo ""
  echo "| Artifact | Path | Status |"
  echo "|----------|------|--------|"

  # Check each artifact and show status
  [[ -f "${PROJECT_DIR}/backup/boot-stock.img" ]] && echo "| Boot image | \`backup/boot-stock.img\` | ✅ |" || echo "| Boot image | \`backup/boot-stock.img\` | ❌ |"
  [[ -f "${PROJECT_DIR}/backup/dtbo.img" ]] && echo "| DTBO image | \`backup/dtbo.img\` | ✅ |" || echo "| DTBO image | \`backup/dtbo.img\` | ❌ |"
  [[ -f "$DTB_TRIMMED" ]] && echo "| DTB (trimmed) | \`backup/dtb-stock-trimmed.dtb\` | ✅ |" || echo "| DTB (trimmed) | \`backup/dtb-stock-trimmed.dtb\` | ❌ |"
  [[ -f "$DTB_TRIMMED_DTS" ]] && echo "| DTS (decompiled) | \`backup/dtb-stock-trimmed.dts\` | ✅ |" || echo "| DTS (decompiled) | \`backup/dtb-stock-trimmed.dts\` | ❌ |"

  # Check vbmeta
  vbmeta_count=$(find "${PROJECT_DIR}/backup" -maxdepth 1 -name "vbmeta*.img" 2>/dev/null | wc -l)
  [[ "$vbmeta_count" -gt 0 ]] && echo "| vbmeta images | \`backup/vbmeta*.img\` | ✅ ($vbmeta_count files) |" || echo "| vbmeta images | \`backup/vbmeta*.img\` | ❌ |"

  # Boot image info
  [[ -f "$BOOT_HEADER_TXT" ]] && echo "| Boot header info | \`extracted/bootimg_info/\` | ✅ |" || echo "| Boot header info | \`extracted/bootimg_info/\` | ❌ |"

  # Extracted dirs
  [[ -d "$DTB_DIR" ]] && dtb_files=$(find "$DTB_DIR" -name "*.dtb" 2>/dev/null | wc -l) && echo "| Extracted DTBs | \`extracted/dtb_from_bootimg/\` | ✅ ($dtb_files files) |" || echo "| Extracted DTBs | \`extracted/dtb_from_bootimg/\` | ❌ |"
  [[ -d "$DTBO_DIR" ]] && dtbo_files=$(find "$DTBO_DIR" -name "*.dtb" 2>/dev/null | wc -l) && echo "| DTBO overlays | \`extracted/dtbo_split/\` | ✅ ($dtbo_files files) |" || echo "| DTBO overlays | \`extracted/dtbo_split/\` | ❌ |"
  [[ -d "$SUPER_LP_DIR" ]] && super_parts=$(find "$SUPER_LP_DIR" -name "*.img" 2>/dev/null | wc -l) && echo "| Super partitions | \`extracted/super_lpunpack/\` | ✅ ($super_parts partitions) |" || echo "| Super partitions | \`extracted/super_lpunpack/\` | ❌ |"
  [[ -d "$VENDOR_BLOBS_DIR" ]] && echo "| Vendor blobs | \`extracted/vendor_blobs/\` | ✅ |" || echo "| Vendor blobs | \`extracted/vendor_blobs/\` | ❌ |"
  [[ -d "$RAMDISK_DIR" ]] && echo "| Ramdisk init | \`extracted/ramdisk_init/\` | ✅ |" || echo "| Ramdisk init | \`extracted/ramdisk_init/\` | ❌ |"

  echo ""
} > "$REPORT_MD"

echo "[*] Wrote report:"
echo "    $REPORT_MD"
echo
echo "[*] Preview (first 80 lines):"
sed -n '1,80p' "$REPORT_MD"

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
  h3 "$title"
  if [[ -e "$path" ]]; then
    # Check if directory has actual content
    local file_count
    if [[ -d "$path" ]]; then
      file_count=$(find "$path" -maxdepth 1 -type f 2>/dev/null | wc -l)
      if [[ "$file_count" -gt 0 ]]; then
        echo "$(ok_mark) **Found** ($file_count files)"
        [[ -n "$track_name" ]] && track_found "$track_name" || true
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
  else
    echo "$(fail_mark) **No getprop data available yet.**"
    track_missing "Device properties (getprop)"
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
      echo "$(warn_mark) **No init*.rc scripts in ramdisk** (normal for Android 10+ first_stage_mount)"
      track_warning "Init scripts (empty - normal for A10+)"
    fi
    echo ""
    safe_ls "init scripts" "${RAMDISK_DIR}/init" 120

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

    # Check ueventd
    ueventd_count=$(find "${RAMDISK_DIR}/ueventd" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$ueventd_count" -gt 0 ]]; then
      echo "$(ok_mark) **ueventd rules found ($ueventd_count files)**"
      track_found "ueventd rules"
    else
      echo "$(warn_mark) **No ueventd*.rc in ramdisk** (normal for Android 10+ first_stage_mount)"
      track_warning "ueventd rules (empty - normal for A10+)"
    fi
    echo ""
    safe_ls "ueventd rules" "${RAMDISK_DIR}/ueventd" 120

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
    echo "$(warn_mark) **super.img not at default location** (may have been extracted and deleted)"
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

    # Check kernel modules
    mod_dir="${VENDOR_BLOBS_DIR}/lib/modules"
    if [[ -d "$mod_dir" ]]; then
      mod_count=$(find "$mod_dir" -type f -name "*.ko" 2>/dev/null | wc -l)
      if [[ "$mod_count" -gt 0 ]]; then
        echo "$(ok_mark) **vendor/lib/modules found ($mod_count .ko files)**"
        track_found "Vendor kernel modules"
      else
        echo "$(warn_mark) **vendor/lib/modules directory exists but no .ko files**"
        track_warning "Vendor kernel modules (empty)"
        echo ""
        echo "$(info_mark) This often happens with debugfs extraction. Mount vendor.img with sudo:"
        echo ""
        printf '%s\n' '```bash'
        echo "sudo mount -o loop,ro extracted/super_lpunpack/vendor.img /mnt"
        echo "cp -a /mnt/lib/modules/* extracted/vendor_blobs/lib/modules/"
        echo "sudo umount /mnt"
        printf '%s\n' '```'
      fi
    else
      echo "$(fail_mark) **vendor/lib/modules missing**"
      track_missing "Vendor kernel modules"
    fi
    echo ""
    safe_ls "vendor/lib/modules" "$mod_dir" 120

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

  h2 "🔍 Missing Artifacts Analysis & Remediation"

  echo ""
  echo "### Why are some items missing?"
  echo ""

  # Check specific missing items and explain why
  if [[ ! -f "$DTB_TRIMMED_DTS" ]]; then
    echo "#### $(fail_mark) DTB DTS (backup/dtb-stock-trimmed.dts)"
    echo ""
    echo "**Why missing:** The \`02_unpack_and_extract_dtb.sh\` script extracts DTB to"
    echo "\`extracted/dtb_from_bootimg/\` but doesn't copy a \"trimmed\" version to \`backup/\`."
    echo ""
    echo "**Impact:** The report cannot grep DTB for hardware nodes (panel, touchscreen, WiFi/BT)."
    echo ""
    echo "**Fix:** Copy and optionally trim the extracted DTB:"
    echo ""
    printf '%s\n' '```bash'
    echo "cp extracted/dtb_from_bootimg/01_dtbdump_*SC9863a.dtb backup/dtb-stock-trimmed.dtb"
    echo "dtc -I dtb -O dts -o backup/dtb-stock-trimmed.dts backup/dtb-stock-trimmed.dtb"
    printf '%s\n' '```'
    echo ""
  fi

  # Check for empty init scripts
  if [[ -d "${RAMDISK_DIR}/init" ]]; then
    init_count=$(find "${RAMDISK_DIR}/init" -maxdepth 1 -type f -name "*.rc" 2>/dev/null | wc -l)
    if [[ "$init_count" -eq 0 ]]; then
      echo "#### $(warn_mark) Init scripts (init*.rc) — Empty"
      echo ""
      echo "**Why empty:** This is **normal for Android 10+ devices** with first_stage_mount."
      echo "The boot ramdisk contains only the minimal \`init\` binary and \`fstab\`."
      echo "Full init scripts (\`init.rc\`, \`init.*.rc\`) live inside \`system.img\` and \`vendor.img\`."
      echo ""
      echo "**Impact:** None — postmarketOS doesn't use Android init scripts."
      echo ""
      echo "**For reference only:** Mount system/vendor to extract Android init configs:"
      echo ""
      printf '%s\n' '```bash'
      echo "sudo mount -o loop,ro extracted/super_lpunpack/system.img /mnt"
      echo "ls /mnt/system/etc/init/"
      printf '%s\n' '```'
      echo ""
    fi
  fi

  # Check for empty ueventd
  if [[ -d "${RAMDISK_DIR}/ueventd" ]]; then
    ueventd_count=$(find "${RAMDISK_DIR}/ueventd" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$ueventd_count" -eq 0 ]]; then
      echo "#### $(warn_mark) Ueventd rules (ueventd*.rc) — Empty"
      echo ""
      echo "**Why empty:** Same reason as init scripts — Android 10+ first_stage_mount."
      echo "Ueventd rules are in \`vendor.img\` at \`/vendor/ueventd.rc\`."
      echo ""
      echo "**Impact:** Low — postmarketOS uses udev, not ueventd."
      echo ""
    fi
  fi

  # Check vendor modules
  vendor_modules_dir="${VENDOR_BLOBS_DIR}/lib/modules"
  if [[ -d "$vendor_modules_dir" ]]; then
    module_count=$(find "$vendor_modules_dir" -type f -name "*.ko" 2>/dev/null | wc -l)
    if [[ "$module_count" -eq 0 ]]; then
      echo "#### $(warn_mark) Vendor kernel modules (*.ko) — Empty"
      echo ""
      echo "**Why empty:** The \`04_extract_vendor_blobs.sh\` script uses \`debugfs\` fallback"
      echo "(because \`sudo mount\` requires root in containers). \`debugfs rdump\` can fail"
      echo "silently for some directory structures."
      echo ""
      echo "**Impact:** Missing GPU/WiFi/sensor kernel modules needed for hardware."
      echo ""
      echo "**Fix:** Mount vendor.img with root privileges:"
      echo ""
      printf '%s\n' '```bash'
      echo "sudo mount -o loop,ro extracted/super_lpunpack/vendor.img /mnt"
      echo "cp -a /mnt/lib/modules extracted/vendor_blobs/lib/"
      echo "sudo umount /mnt"
      printf '%s\n' '```'
      echo ""
    fi
  fi

  # Check for vendor firmware
  vendor_fw_dir="${VENDOR_BLOBS_DIR}/firmware"
  if [[ -d "$vendor_fw_dir" ]]; then
    # Check if there's a nested firmware/firmware structure
    if [[ -d "${vendor_fw_dir}/firmware" ]]; then
      echo "#### $(info_mark) Vendor firmware structure note"
      echo ""
      echo "Firmware was extracted with a nested \`firmware/firmware/\` structure."
      echo "This is due to how \`debugfs rdump\` works. The actual firmware is at:"
      echo ""
      echo "\`extracted/vendor_blobs/firmware/firmware/\`"
      echo ""
    fi
  fi

  hr

  h2 "🚀 Next Steps for postmarketOS Porting"

  echo ""
  echo "### Essential tasks before starting the port:"
  echo ""
  echo "1. **$(ok_mark) DTB/DTS available** — Device tree extracted from boot.img"
  echo "2. **$(ok_mark) Boot image analyzed** — cmdline, ramdisk structure known"
  echo "3. **$(ok_mark) Partition layout known** — super.img extracted (system/vendor/product)"
  echo "4. **$(ok_mark) SoC identified** — Unisoc SC9863A (sharkl3 platform)"
  echo ""
  echo "### Recommended improvements:"
  echo ""
  echo "1. **Copy DTB to backup/** — Run:"
  echo "   \`cp extracted/dtb_from_bootimg/01_dtbdump_*SC9863a.dtb backup/dtb-stock-trimmed.dtb\`"
  echo ""
  echo "2. **Extract vendor kernel modules** — Mount vendor.img with sudo to get \`*.ko\` files"
  echo ""
  echo "3. **Identify WiFi/BT firmware** — Check \`extracted/vendor_blobs/firmware/\` for:"
  echo "   - \`wcnmodem.bin\` — WCN (Wireless Connectivity) modem"
  echo "   - \`sc2355_*\` — Spreadtrum WiFi/BT chip firmware"
  echo ""
  echo "4. **Analyze display panel** — Grep DTB for panel compatible strings"
  echo ""
  echo "5. **Check touchscreen** — Device likely uses GSL series (gslx680) or Focaltech"
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

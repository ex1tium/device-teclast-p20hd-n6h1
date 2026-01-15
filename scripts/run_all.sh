#!/usr/bin/env bash
# Interactive runner for Teclast P20HD bringup scripts (00..10)
# - Tracks progress via logs/.state/*.ok
# - Logs output per step
# - On failure: retry / skip / abort / view log

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
STATE_DIR="${LOG_DIR}/.state"
mkdir -p "${LOG_DIR}" "${STATE_DIR}"

# ---------------------------
# Pretty output helpers
# ---------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  RESET=$'\033[0m'
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

info()  { echo "${BLUE}[INFO]${RESET}  $*"; }
ok()    { echo "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo "${RED}[ERR]${RESET}   $*"; }
hr() { echo "${DIM}------------------------------------------------------------${RESET}"; }

# ---------------------------
# CLI options
# ---------------------------
NON_INTERACTIVE=0
FROM_STEP="00"
FORCE=0
FIRMWARE_RAR="${FIRMWARE_RAR:-}"
SUPER_IMG="${SUPER_IMG:-}"

usage() {
  cat <<EOF
${BOLD}run_all.sh${RESET} — interactive bringup pipeline runner

Usage:
  bash scripts/run_all.sh [options]

Options:
  --firmware <path>   Path to official firmware .rar (Roshal archive)
  --super <path>      Path to super.img (Android dynamic partitions container)
  --from <NN>         Start from step NN (00..10)
  --force             Re-run steps even if logs/.state/NN.ok exists
  -y, --yes           Non-interactive (auto-skip on failures)
  -h, --help          Show help

Examples:
  bash scripts/run_all.sh --firmware ~/Downloads/P20HD_EEA_Firmware.rar
  bash scripts/run_all.sh --from 03
  bash scripts/run_all.sh -y
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firmware)
      FIRMWARE_RAR="${2:-}"
      # Convert to absolute path if relative
      if [[ -n "${FIRMWARE_RAR}" && "${FIRMWARE_RAR}" != /* && -f "${FIRMWARE_RAR}" ]]; then
        FIRMWARE_RAR="$(cd "$(dirname "${FIRMWARE_RAR}")" && pwd)/$(basename "${FIRMWARE_RAR}")"
      fi
      shift 2;;
    --super)
      SUPER_IMG="${2:-}"
      # Convert to absolute path if relative
      if [[ -n "${SUPER_IMG}" && "${SUPER_IMG}" != /* && -f "${SUPER_IMG}" ]]; then
        SUPER_IMG="$(cd "$(dirname "${SUPER_IMG}")" && pwd)/$(basename "${SUPER_IMG}")"
      fi
      shift 2;;
    --from)     FROM_STEP="${2:-}"; shift 2;;
    --force)    FORCE=1; shift;;
    -y|--yes)   NON_INTERACTIVE=1; shift;;
    -h|--help)  usage; exit 0;;
    *) err "Unknown argument: $1"; usage; exit 2;;
  esac
done

# ---------------------------
# Step definitions
# ---------------------------
STEPS=(
  "00|00_devtools.sh|Install toolchain + setup workspace"
  "01|01_extract_firmware.sh|Extract firmware (.rar → .pac → boot/dtbo/vbmeta/super)"
  "02|02_unpack_and_extract_dtb.sh|Unpack boot.img + extract DTB (Device Tree Blob)"
  "03|03_unpack_super_img.sh|Unpack super.img (dynamic partitions) via lpunpack"
  "04|04_extract_vendor_blobs.sh|Extract vendor blobs for bringup"
  "05|05_collect_device_info.sh|Collect device runtime info via ADB (Android Debug Bridge — USB device communication)"
  "06|06_extract_kernel_info.sh|Extract kernel strings/config hints"
  "07|07_extract_vbmeta_info.sh|Parse vbmeta images (Android Verified Boot metadata)"
  "08|08_split_dtbo_overlays.sh|Split dtbo.img overlays (Device Tree Blob Overlays)"
  "09|09_extract_ramdisk_init.sh|Extract init/fstab/ueventd from ramdisk"
  "10|10_bringup_report.sh|Generate bringup report summary"
)

step_ge() { local a="$1" b="$2"; ((10#$a >= 10#$b)); }
script_path() { echo "${SCRIPT_DIR}/$1"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------
# Smart defaults / detection
# ---------------------------
detect_super_img() {
  if [[ -n "${SUPER_IMG}" && -f "${SUPER_IMG}" ]]; then echo "${SUPER_IMG}"; return 0; fi
  local candidates=(
    "${PROJECT_DIR}/firmware/super.img"
    "${PROJECT_DIR}/firmware/extracted_pac/super.img"
    "${PROJECT_DIR}/backup/super.img"
  )
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  echo ""
}

detect_firmware_rar() {
  if [[ -n "${FIRMWARE_RAR}" && -f "${FIRMWARE_RAR}" ]]; then
    echo "${FIRMWARE_RAR}"
    return 0
  fi

  local hits=()
  while IFS= read -r -d '' f; do hits+=("$f"); done < <(find "${PROJECT_DIR}" -maxdepth 1 -type f -iname "*.rar" -print0 2>/dev/null || true)
  while IFS= read -r -d '' f; do hits+=("$f"); done < <(find "${PROJECT_DIR}/firmware" -maxdepth 1 -type f -iname "*.rar" -print0 2>/dev/null || true)

  if [[ "${#hits[@]}" -eq 1 ]]; then
    echo "${hits[0]}"
    return 0
  fi

  echo ""
}

confirm() {
  local prompt="$1"
  [[ "${NON_INTERACTIVE}" -eq 1 ]] && return 0
  read -r -p "${prompt} [Y/n] " ans || true
  case "${ans:-Y}" in n|N|no|NO) return 1;; *) return 0;; esac
}

pick_action_on_fail() {
  local log="$1"
  [[ "${NON_INTERACTIVE}" -eq 1 ]] && { echo "skip"; return 0; }

  echo
  warn "Choose action: ${BOLD}[r]etry${RESET}, ${BOLD}[s]kip${RESET}, ${BOLD}[a]bort${RESET}, ${BOLD}[v]iew log${RESET}"
  while true; do
    read -r -p "> " act || true
    case "${act,,}" in
      r|retry) echo "retry"; return 0;;
      s|skip)  echo "skip";  return 0;;
      a|abort) echo "abort"; return 0;;
      v|view)
        hr
        info "Showing tail of log: ${log}"
        tail -n 120 "${log}" || true
        hr
        ;;
      *) echo "Type r / s / a / v";;
    esac
  done
}

run_step() {
  local step_id="$1" step_script="$2" step_desc="$3"
  local spath log rc

  spath="$(script_path "${step_script}")"
  [[ -f "${spath}" ]] || { err "Missing script: ${spath}"; return 127; }

  log="${LOG_DIR}/${step_id}_${step_script}.log"

  hr
  echo "${BOLD}Step ${step_id}${RESET} — ${step_desc}"
  echo "${DIM}${spath}${RESET}"
  echo "${DIM}Log: ${log}${RESET}"
  hr

  local args=()

  if [[ "${step_id}" == "01" ]]; then
    local rar
    rar="$(detect_firmware_rar)"
    if [[ -z "${rar}" ]]; then
      warn "Step 01 needs a firmware .rar path."
      if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
        err "No firmware path provided. Use --firmware /path/to/file.rar"
        return 2
      fi
      read -r -p "Enter firmware .rar path: " rar
    fi
    [[ -f "${rar}" ]] || { err "Firmware .rar not found: ${rar}"; return 2; }
    args+=("${rar}")
  fi

  if [[ "${step_id}" == "03" ]]; then
    if ! need_cmd lpunpack; then
      warn "lpunpack (Logical Partition unpack — super.img extractor) not found in PATH."
      warn "Fix: run Step 00 first (it installs a working lpunpack wrapper)."
      if ! confirm "Continue anyway?"; then
        return 3
      fi
    fi
    local s
    s="$(detect_super_img)"
    if [[ -z "${s}" ]]; then
      warn "Could not auto-detect super.img."
      if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
        err "No super.img path provided. Use --super firmware/super.img"
        return 2
      fi
      read -r -p "Enter super.img path: " s
    fi
    [[ -f "${s}" ]] || { err "super.img not found: ${s}"; return 2; }
    args+=("${s}")
  fi

  info "Running: bash ${step_script} ${args[*]:-}"
  (
    cd "${PROJECT_DIR}"
    set +e
    bash "${spath}" "${args[@]}" 2>&1 | tee "${log}"
    exit "${PIPESTATUS[0]}"
  )
  rc=$?

  if [[ $rc -eq 0 ]]; then
    ok "Step ${step_id} succeeded."
    touch "${STATE_DIR}/${step_id}.ok"
  else
    err "Step ${step_id} FAILED (exit ${rc})."
    warn "Log: ${log}"
    rm -f "${STATE_DIR}/${step_id}.ok" 2>/dev/null || true
  fi

  return "${rc}"
}

# ---------------------------
# Main run
# ---------------------------
echo "${BOLD}Teclast P20HD bringup pipeline — run_all.sh${RESET}"
echo "Project: ${PROJECT_DIR}"
echo "Logs:    ${LOG_DIR}"
echo "Mode:    $([[ "${NON_INTERACTIVE}" -eq 1 ]] && echo "non-interactive (-y)" || echo "interactive")"
echo "From:    ${FROM_STEP}"
echo "Force:   $([[ "${FORCE}" -eq 1 ]] && echo "yes" || echo "no")"
hr

declare -A RESULTS=()
FAILED=0
SKIPPED=0
OKCOUNT=0

for line in "${STEPS[@]}"; do
  IFS='|' read -r sid sfile sdesc <<< "${line}"

  if ! step_ge "${sid}" "${FROM_STEP}"; then
    RESULTS["${sid}"]="SKIP(from)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ "${FORCE}" -eq 0 && -f "${STATE_DIR}/${sid}.ok" ]]; then
    warn "Step ${sid} already completed (${STATE_DIR}/${sid}.ok)."
    if ! confirm "Re-run Step ${sid}?"; then
      RESULTS["${sid}"]="SKIP(done)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  while true; do
    if run_step "${sid}" "${sfile}" "${sdesc}"; then
      RESULTS["${sid}"]="OK"
      OKCOUNT=$((OKCOUNT + 1))
      break
    else
      RESULTS["${sid}"]="FAIL"
      FAILED=$((FAILED + 1))
      local_log="${LOG_DIR}/${sid}_${sfile}.log"
      action="$(pick_action_on_fail "${local_log}")"
      case "${action}" in
        retry) continue ;;
        skip) warn "Skipping Step ${sid}."; RESULTS["${sid}"]="SKIP(fail)"; SKIPPED=$((SKIPPED + 1)); break ;;
        abort) err "Aborting pipeline on Step ${sid}."; break 2 ;;
      esac
    fi
  done
done

hr
echo "${BOLD}Pipeline summary${RESET}"
hr

for line in "${STEPS[@]}"; do
  IFS='|' read -r sid sfile sdesc <<< "${line}"
  status="${RESULTS[${sid}]:-SKIP}"
  case "${status}" in
    OK)    echo "${GREEN}✔${RESET} ${sid} ${sfile}  ${DIM}${sdesc}${RESET}" ;;
    FAIL)  echo "${RED}✘${RESET} ${sid} ${sfile}  ${DIM}${sdesc}${RESET}" ;;
    SKIP*) echo "${YELLOW}↷${RESET} ${sid} ${sfile}  ${DIM}${sdesc} (${status})${RESET}" ;;
    *)     echo "${YELLOW}?${RESET} ${sid} ${sfile}  ${DIM}${sdesc} (${status})${RESET}" ;;
  esac
done

hr
echo "${BOLD}Counts${RESET}"
echo "  OK:      ${OKCOUNT}"
echo "  Skipped: ${SKIPPED}"
echo "  Failed:  ${FAILED}"

hr
echo "Logs live in: ${LOG_DIR}"
echo "State files:  ${STATE_DIR}"
hr

exit 0

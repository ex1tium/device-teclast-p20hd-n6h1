#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTDIR="$PROJECT_DIR/extracted/vbmeta_info"
mkdir -p "$OUTDIR"

VBMETA_DIR="$PROJECT_DIR/backup"
if [[ ! -d "$VBMETA_DIR" ]]; then
  echo "ERROR: missing $VBMETA_DIR"
  exit 1
fi

ensure_avbtool() {
  if command -v avbtool >/dev/null 2>&1; then
    echo "avbtool"
    return 0
  fi

  local TOOL_DIR="$PROJECT_DIR/tools/avb"
  local TOOL="$TOOL_DIR/avbtool.py"
  mkdir -p "$TOOL_DIR"

  if [[ ! -f "$TOOL" ]]; then
    echo "[*] avbtool not found -> downloading from AOSP..."
    if ! command -v curl >/dev/null 2>&1; then
      echo "ERROR: curl not found."
      exit 2
    fi
    if ! command -v base64 >/dev/null 2>&1; then
      echo "ERROR: base64 not found."
      exit 3
    fi

    # AOSP "format=TEXT" returns base64-encoded content
    curl -fsSL "https://android.googlesource.com/platform/external/avb/+/refs/heads/master/avbtool?format=TEXT" \
      | base64 -d > "$TOOL"
    chmod +x "$TOOL"
  fi

  echo "python3 $TOOL"
}

AVBTOOL_CMD="$(ensure_avbtool)"

echo "[*] Using: $AVBTOOL_CMD"
echo

mapfile -t IMAGES < <(find "$VBMETA_DIR" -maxdepth 1 -type f -name "vbmeta*.img" -o -name "vbmeta-*.img" | sort)
if [[ "${#IMAGES[@]}" -eq 0 ]]; then
  echo "ERROR: No vbmeta images found in $VBMETA_DIR"
  exit 4
fi

for img in "${IMAGES[@]}"; do
  base="$(basename "$img")"
  out="$OUTDIR/${base}.info.txt"
  echo "[*] vbmeta -> $base"
  # shellcheck disable=SC2086
  $AVBTOOL_CMD info_image --image "$img" > "$out" 2>&1 || true
done

echo
echo "[*] Summary (verified partitions):"
grep -R "Partition Name:" -n "$OUTDIR" | head -n 120 || true

echo
echo "[*] Done. Outputs in: $OUTDIR"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUPER_IMG="${1:-$PROJECT_DIR/firmware/super.img}"
OUTDIR="${2:-$PROJECT_DIR/extracted/super_lpunpack}"

mkdir -p "$OUTDIR"
mkdir -p "$PROJECT_DIR/extracted"

# If default path isn't correct, try to find it automatically.
if [[ ! -f "$SUPER_IMG" ]]; then
  FOUND="$(find "$PROJECT_DIR/firmware" -maxdepth 4 -type f -name "super.img" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$FOUND" ]]; then
    SUPER_IMG="$FOUND"
  fi
fi

if [[ ! -f "$SUPER_IMG" ]]; then
  echo "ERROR: super.img not found."
  echo "Tried: $SUPER_IMG"
  echo "Hint: find $PROJECT_DIR/firmware -maxdepth 4 -name super.img"
  exit 1
fi

echo "[*] super.img: $SUPER_IMG"
file "$SUPER_IMG" || true

# Tool selection
LPUNPACK_BIN="$(command -v lpunpack 2>/dev/null || true)"
LPUNPACK_PY="$PROJECT_DIR/tools/lpunpack/lpunpack.py"

if [[ -z "$LPUNPACK_BIN" && ! -f "$LPUNPACK_PY" ]]; then
  echo "ERROR: Neither 'lpunpack' nor '$LPUNPACK_PY' exists."
  echo ""
  echo "Fix (recommended):"
  echo "  mkdir -p $PROJECT_DIR/tools/lpunpack"
  echo "  # put your lpunpack.py there as: tools/lpunpack/lpunpack.py"
  exit 2
fi

# Convert sparse -> raw if needed
RAW_IMG="$PROJECT_DIR/extracted/super.raw.img"
if file "$SUPER_IMG" | grep -qi "sparse"; then
  # Prefer system simg2img (works correctly) over local builds that may have broken deps
  SIMG2IMG_BIN=""
  for candidate in /usr/bin/simg2img "$(command -v simg2img 2>/dev/null || true)"; do
    if [[ -x "$candidate" ]]; then
      # Test that the binary can actually run (not missing libs)
      # simg2img prints "Usage:" to stderr when run without args
      # Use a subshell without pipefail to avoid exit code issues
      if ( set +o pipefail; "$candidate" 2>&1 | grep -q "Usage:" ); then
        SIMG2IMG_BIN="$candidate"
        break
      fi
    fi
  done

  if [[ -z "$SIMG2IMG_BIN" ]]; then
    echo "ERROR: simg2img not found or broken (Android sparse converter)."
    echo "Install: sudo apt install -y android-sdk-libsparse-utils"
    exit 3
  fi

  if [[ ! -f "$RAW_IMG" || ! -s "$RAW_IMG" ]]; then
    echo "[*] Sparse super.img detected -> converting to raw: $RAW_IMG"
    echo "[*] Using: $SIMG2IMG_BIN"
    "$SIMG2IMG_BIN" "$SUPER_IMG" "$RAW_IMG"
  else
    echo "[*] Raw super image already exists: $RAW_IMG"
  fi

  SUPER_IMG="$RAW_IMG"
fi

echo "[*] Unpacking super.img -> $OUTDIR"
rm -f "$OUTDIR"/*.img 2>/dev/null || true

if [[ -n "$LPUNPACK_BIN" ]]; then
  echo "[*] Using binary lpunpack: $LPUNPACK_BIN"
  # Some lpunpack versions don't support -v, try without if it fails
  "$LPUNPACK_BIN" "$SUPER_IMG" "$OUTDIR" || "$LPUNPACK_BIN" -v "$SUPER_IMG" "$OUTDIR"
else
  echo "[*] Using python lpunpack: $LPUNPACK_PY"
  python3 "$LPUNPACK_PY" "$SUPER_IMG" "$OUTDIR"
fi

echo
echo "[*] Done. Extracted logical partitions:"
ls -lh "$OUTDIR" | head -n 120

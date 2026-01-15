#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DTBO_IMG="${1:-$PROJECT_DIR/backup/dtbo.img}"
OUTDIR="${2:-$PROJECT_DIR/extracted/dtbo_split}"

mkdir -p "$OUTDIR"

# Auto-find dtbo.img if default missing
if [[ ! -f "$DTBO_IMG" ]]; then
  FOUND="$(find "$PROJECT_DIR" -maxdepth 4 -type f -name "dtbo.img" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$FOUND" ]]; then
    DTBO_IMG="$FOUND"
  fi
fi

if [[ ! -f "$DTBO_IMG" ]]; then
  echo "ERROR: dtbo.img not found."
  echo "Tried: $DTBO_IMG"
  echo "Hint: find $PROJECT_DIR -maxdepth 4 -name dtbo.img"
  exit 1
fi

if ! command -v dtc >/dev/null 2>&1; then
  echo "ERROR: dtc not found (Device Tree Compiler)."
  echo "Install: sudo apt install -y device-tree-compiler"
  exit 2
fi

echo "[*] DTBO image: $DTBO_IMG"
file "$DTBO_IMG" || true
echo "[*] Output dir: $OUTDIR"

# Export for Python heredoc
export DTBO_IMG="$DTBO_IMG"
export OUTDIR="$OUTDIR"

python3 - <<'PY'
import os, struct

DT_TABLE_MAGIC = 0xD7B7AB1E

def u32(data, off, endian):
    return struct.unpack_from(endian + "I", data, off)[0]

def detect_endian(data):
    if u32(data, 0, ">") == DT_TABLE_MAGIC:
        return ">"
    if u32(data, 0, "<") == DT_TABLE_MAGIC:
        return "<"
    return None

dtbo_path = os.environ["DTBO_IMG"]
outdir = os.environ["OUTDIR"]

with open(dtbo_path, "rb") as f:
    data = f.read()

endian = detect_endian(data)
if endian is None:
    raise SystemExit("ERROR: DTBO magic not found (not a DTBO image?)")

header_size    = u32(data,  4, endian)
entry_size     = u32(data, 12, endian)
entry_count    = u32(data, 16, endian)
entries_offset = u32(data, 20, endian)

print(f"DTBO: endian={'big' if endian=='>' else 'little'} | header_size={header_size} | entries={entry_count} | entry_size={entry_size}")

os.makedirs(outdir, exist_ok=True)

# idempotent: clear old extracted overlays
for fn in os.listdir(outdir):
    if fn.endswith(".dtb") and fn.startswith("dtbo_"):
        os.remove(os.path.join(outdir, fn))

for i in range(entry_count):
    eoff = entries_offset + i * entry_size
    dt_size = u32(data, eoff + 0, endian)
    dt_off  = u32(data, eoff + 4, endian)
    dt_id   = u32(data, eoff + 8, endian)
    dt_rev  = u32(data, eoff + 12, endian)

    blob = data[dt_off:dt_off+dt_size]
    out = os.path.join(outdir, f"dtbo_{i:03d}_id{dt_id:08x}_rev{dt_rev:08x}.dtb")
    with open(out, "wb") as f:
        f.write(blob)

print(f"Extracted overlays into {outdir}")
PY

echo
echo "[*] Decompiling DTBs -> DTS..."
shopt -s nullglob
for f in "$OUTDIR"/*.dtb; do
  dts="${f%.dtb}.dts"
  # idempotent: overwrite each time
  dtc -I dtb -O dts -o "$dts" "$f" 2>"$dts.warnings.txt" || true
done
shopt -u nullglob

echo
echo "[*] Done. Extracted overlays:"
ls -lh "$OUTDIR" | head -n 120

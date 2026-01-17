#!/usr/bin/env bash
set -euo pipefail

# Teclast P20HD postmarketOS bringup - development environment bootstrap
# Idempotent: safe to run multiple times.
#
# Options:
#   --upgrade        Run apt upgrade -y (disabled by default)
#   --update-tools   Update git tool repos (AIK/pacextractor/pmbootstrap/pmaports) if clean
#   --reclone-tools  Delete and re-clone tool repos (destructive)
#
# Notes:
# - postmarketOS moved to https://gitlab.postmarketos.org (pmbootstrap/pmaports) :contentReference[oaicite:2]{index=2}
# - By default, this script will NOT touch tool repos that may have local changes,
#   unless --update-tools or --reclone-tools is used.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

UPGRADE=0
UPDATE_TOOLS=0
RECLONE_TOOLS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade)       UPGRADE=1; shift;;
    --update-tools)  UPDATE_TOOLS=1; shift;;
    --reclone-tools) RECLONE_TOOLS=1; shift;;
    -h|--help)
      cat <<EOF
00_devtools.sh — environment bootstrap

Usage:
  ./scripts/00_devtools.sh [--upgrade] [--update-tools] [--reclone-tools]

Options:
  --upgrade        apt upgrade -y (default: off)
  --update-tools   git pull tool repos if clean (default: off)
  --reclone-tools  delete + re-clone tool repos (destructive)
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

echo "=== Teclast P20HD Development Environment Setup ==="
echo "Project directory: $PROJECT_DIR"

if ! command -v apt >/dev/null 2>&1; then
  echo "ERROR: apt not found. This script targets Debian/Ubuntu-style systems."
  exit 1
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

git_is_clean() {
  local dir="$1"
  ( cd "$dir" && git diff --quiet && git diff --cached --quiet )
}

git_set_remote_if_needed() {
  local dir="$1" remote_name="$2" wanted_url="$3"
  local current_url=""
  current_url="$(cd "$dir" && git remote get-url "$remote_name" 2>/dev/null || true)"
  if [[ -n "$current_url" && "$current_url" != "$wanted_url" ]]; then
    echo "[*] Updating remote $remote_name URL:"
    echo "    from: $current_url"
    echo "      to: $wanted_url"
    ( cd "$dir" && git remote set-url "$remote_name" "$wanted_url" )
  fi
}

git_clone_or_update() {
  local url="$1" dir="$2" branch="${3:-}" name="${4:-repo}" shallow="${5:-0}"

  if [[ "$RECLONE_TOOLS" -eq 1 && -d "$dir" ]]; then
    echo "[*] --reclone-tools: removing $name at $dir"
    rm -rf "$dir"
  fi

  if [[ ! -d "$dir/.git" ]]; then
    echo "[*] Cloning $name..."
    if [[ -n "$branch" ]]; then
      git clone --depth=1 --branch "$branch" "$url" "$dir"
    elif [[ "$shallow" -eq 1 ]]; then
      git clone --depth=1 "$url" "$dir"
    else
      git clone "$url" "$dir"
    fi
    return 0
  fi

  # Existing clone
  if [[ "$UPDATE_TOOLS" -eq 0 ]]; then
    echo "[*] $name already present, not updating automatically."
    echo "    (Use --update-tools to pull updates, or --reclone-tools to re-clone.)"
    return 0
  fi

  # Update only if clean
  if ! git_is_clean "$dir"; then
    echo "[!] $name has local changes; skipping update:"
    echo "    $dir"
    echo "    (Commit/stash changes, or use --reclone-tools if disposable.)"
    return 0
  fi

  echo "[*] Updating $name (fast-forward only)..."
  ( cd "$dir" && git fetch --all --prune && git pull --ff-only )
}

ensure_path_line='export PATH="$HOME/.local/bin:$PATH"'
ensure_user_path() {
  # bash + zsh friendly; harmless if user uses only one shell
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -e "$rc" ]] || continue
    if ! grep -qF "$ensure_path_line" "$rc"; then
      echo "$ensure_path_line" >> "$rc"
    fi
  done
  export PATH="$HOME/.local/bin:$PATH"
}

# -----------------------------------------------------------------------------
# System packages
# -----------------------------------------------------------------------------
echo "[1/7] Updating package lists..."
sudo apt update

if [[ "$UPGRADE" -eq 1 ]]; then
  echo "[1/7] Upgrading packages (--upgrade)..."
  sudo apt upgrade -y
else
  echo "[1/7] Skipping apt upgrade (use --upgrade to enable)."
fi

echo "[2/7] Installing base development tools..."
sudo apt install -y --no-install-recommends \
  ca-certificates \
  git curl wget vim nano \
  build-essential \
  bc bison flex \
  libssl-dev libncurses-dev libelf-dev \
  python3 python3-pip python3-venv \
  p7zip-full unrar \
  tree jq \
  e2fsprogs \
  file \
  rsync \
  binutils \
  make

echo "[3/7] Installing Android tools (ADB/Fastboot + sparse utils)..."
sudo apt install -y --no-install-recommends \
  android-tools-adb \
  android-tools-fastboot \
  android-sdk-libsparse-utils

echo "[4/7] Installing boot/kernel analysis tools..."
sudo apt install -y --no-install-recommends \
  device-tree-compiler \
  u-boot-tools \
  abootimg \
  binwalk \
  cpio gzip bzip2 lz4 xz-utils \
  unzip zip \
  fuse2fs

echo "[5/7] Installing cross compilation tools..."
sudo apt install -y --no-install-recommends \
  gcc-aarch64-linux-gnu \
  g++-aarch64-linux-gnu

echo "[5/7] Installing optional build toolchain (clang/llvm) for lpunpack source builds..."
sudo apt install -y --no-install-recommends \
  clang lld llvm

echo "[6/7] Installing Python tools..."
python3 -m pip install --user --upgrade pip
python3 -m pip install --user --upgrade \
  extract-dtb \
  pycryptodome

ensure_user_path

echo ""
echo "==> Creating workspace structure..."
mkdir -p "$PROJECT_DIR"/{firmware,backup,extracted,device-info,logs,reports,tools,work,out}

# -----------------------------------------------------------------------------
# AIK (Android Image Kitchen — boot image unpack/repack toolkit)
# -----------------------------------------------------------------------------
AIK_REPO="https://github.com/ndrancs/AIK-Linux-x32-x64.git"
AIK_DIR="$PROJECT_DIR/AIK"

echo ""
echo "==> Setting up AIK (Android Image Kitchen — boot image unpack/repack toolkit)..."
git_clone_or_update "$AIK_REPO" "$AIK_DIR" "" "AIK"
chmod +x "$AIK_DIR"/*.sh 2>/dev/null || true

# Patch stray 'return' if present (harmless but noisy)
if [[ -f "$AIK_DIR/unpackimg_x64.sh" ]] && grep -qE '^[[:space:]]*return[[:space:]]*$' "$AIK_DIR/unpackimg_x64.sh" 2>/dev/null; then
  echo "[*] Patching AIK unpackimg_x64.sh: replacing stray 'return' with 'exit 0'..."
  sed -i -E 's/^[[:space:]]*return[[:space:]]*$/exit 0/' "$AIK_DIR/unpackimg_x64.sh"
fi

# -----------------------------------------------------------------------------
# pacextractor (Spreadtrum/Unisoc .pac extractor)
# -----------------------------------------------------------------------------
PACEX_REPO="https://github.com/divinebird/pacextractor.git"
PACEX_DIR="$PROJECT_DIR/tools/pacextractor"

echo ""
echo "==> Setting up pacextractor (Spreadtrum/Unisoc .pac extractor)..."
git_clone_or_update "$PACEX_REPO" "$PACEX_DIR" "" "pacextractor"

# Reduce build noise: always have a version.h even if git describe fails
echo '#define VERSION_STR "unknown"' > "$PACEX_DIR/version.h"
( cd "$PACEX_DIR" && make )

# -----------------------------------------------------------------------------
# partition_tools (lpunpack/lpmake — Android Logical Partitions utilities)
# -----------------------------------------------------------------------------
echo ""
echo "==> Ensuring lpunpack/lpmake (Logical Partitions utilities) are available..."

need_tools=0
for t in lpunpack lpmake; do
  if ! have_cmd "$t"; then
    need_tools=1
  fi
done

if [[ "$need_tools" -eq 1 ]]; then
  echo "[*] lpunpack/lpmake not found in PATH. Installing local copies into ~/.local/bin ..."
  mkdir -p "$PROJECT_DIR/tools" "$HOME/.local/bin"

  # ---- Option A: try to build from LonelyFool (source) ----
  LF_REPO="https://github.com/LonelyFool/lpunpack_and_lpmake.git"
  LF_DIR="$PROJECT_DIR/tools/lpunpack_and_lpmake"

  git_clone_or_update "$LF_REPO" "$LF_DIR" "" "lpunpack_and_lpmake (source)"
  copied_any=0

  if [[ -d "$LF_DIR" ]]; then
    if [[ -x "$LF_DIR/make.sh" ]]; then
      echo "[*] Running LonelyFool make.sh ..."
      ( cd "$LF_DIR" && bash ./make.sh ) || true
    elif [[ -f "$LF_DIR/Makefile" ]]; then
      echo "[*] Running make ..."
      ( cd "$LF_DIR" && make ) || true
    fi

    for bin in lpunpack lpmake lpdump lpflash; do
      src="$(find "$LF_DIR" -maxdepth 5 -type f -name "$bin" -perm -111 2>/dev/null | head -n 1 || true)"
      if [[ -n "$src" ]]; then
        echo "[*] Installing $bin from source build: $src"
        install -m 0755 "$src" "$HOME/.local/bin/$bin"
        copied_any=1
      fi
    done
  fi

  # ---- Option B: fallback to prebuilt static tools ----
  if [[ "$copied_any" -eq 0 ]]; then
    echo "[*] Source build did not yield binaries. Falling back to prebuilt tools..."
    PREBUILT_REPO="https://github.com/Rprop/aosp15_partition_tools.git"
    PREBUILT_DIR="$PROJECT_DIR/tools/aosp15_partition_tools"

    git_clone_or_update "$PREBUILT_REPO" "$PREBUILT_DIR" "" "aosp15_partition_tools (prebuilt)"

    if [[ -d "$PREBUILT_DIR/linux_glibc_x86_64" ]]; then
      echo "[*] Installing prebuilt partition tools into ~/.local/bin ..."
      for bin in lpunpack lpmake lpdump lpflash ext2simg simg2img; do
        if [[ -f "$PREBUILT_DIR/linux_glibc_x86_64/$bin" ]]; then
          install -m 0755 "$PREBUILT_DIR/linux_glibc_x86_64/$bin" "$HOME/.local/bin/$bin"
        fi
      done
    else
      echo "WARNING: Prebuilt directory missing: $PREBUILT_DIR/linux_glibc_x86_64"
      echo "You can still use your python lpunpack.py fallback."
    fi
  fi
else
  echo "[*] lpunpack/lpmake already available."
fi

# -----------------------------------------------------------------------------
# pmbootstrap (postmarketOS build tool) + pmaports (ports tree reference)
# Updated for gitlab.postmarketos.org migration :contentReference[oaicite:3]{index=3}
# -----------------------------------------------------------------------------
PMBOOTSTRAP_REPO="https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git"
PMAPORTS_REPO="https://gitlab.postmarketos.org/postmarketOS/pmaports.git"

PMBOOTSTRAP_DIR="$PROJECT_DIR/pmbootstrap"
PMAPORTS_DIR="$PROJECT_DIR/pmaports"

echo ""
echo "==> Setting up pmbootstrap (postmarketOS build tool)..."
git_clone_or_update "$PMBOOTSTRAP_REPO" "$PMBOOTSTRAP_DIR" "2.3.x" "pmbootstrap"

# Heal old clones that still point to gitlab.com
if [[ -d "$PMBOOTSTRAP_DIR/.git" ]]; then
  git_set_remote_if_needed "$PMBOOTSTRAP_DIR" "origin" "$PMBOOTSTRAP_REPO"
fi

python3 -m pip install --user --upgrade "$PMBOOTSTRAP_DIR"

echo ""
echo "==> Setting up pmaports (postmarketOS ports tree reference)..."
# Use shallow clone - pmaports is ~2GB full history, ~200MB shallow
git_clone_or_update "$PMAPORTS_REPO" "$PMAPORTS_DIR" "" "pmaports" 1

if [[ -d "$PMAPORTS_DIR/.git" ]]; then
  git_set_remote_if_needed "$PMAPORTS_DIR" "origin" "$PMAPORTS_REPO"
fi

# -----------------------------------------------------------------------------
# spd_dump (Spreadtrum/Unisoc low-level flash tool for Linux)
# Used for recovery when device is stuck in BROM/download mode
# https://github.com/ilyakurdyukov/spreadtrum_flash
# -----------------------------------------------------------------------------
SPD_DUMP_REPO="https://github.com/ilyakurdyukov/spreadtrum_flash.git"
SPD_DUMP_DIR="$PROJECT_DIR/tools/spreadtrum_flash"

echo ""
echo "==> Setting up spd_dump (Spreadtrum/Unisoc low-level flash tool)..."
git_clone_or_update "$SPD_DUMP_REPO" "$SPD_DUMP_DIR" "" "spreadtrum_flash (spd_dump)"

if [[ -d "$SPD_DUMP_DIR" ]]; then
  echo "[*] Building spd_dump..."
  ( cd "$SPD_DUMP_DIR" && make ) || echo "WARNING: spd_dump build failed, may need manual intervention"

  if [[ -f "$SPD_DUMP_DIR/spd_dump" ]]; then
    echo "[*] Installing spd_dump to ~/.local/bin ..."
    install -m 0755 "$SPD_DUMP_DIR/spd_dump" "$HOME/.local/bin/spd_dump"
  fi
fi

# -----------------------------------------------------------------------------
# CVE-2022-38694 Unisoc bootloader unlock/bypass tool
# Used for bypassing vbmeta signature verification on Unisoc devices
# https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader
# -----------------------------------------------------------------------------
CVE_UNLOCK_REPO="https://github.com/TomKing062/CVE-2022-38694_unlock_bootloader.git"
CVE_UNLOCK_DIR="$PROJECT_DIR/tools/CVE-2022-38694_unlock_bootloader"

echo ""
echo "==> Setting up CVE-2022-38694 unlock tool (Unisoc signature bypass)..."
git_clone_or_update "$CVE_UNLOCK_REPO" "$CVE_UNLOCK_DIR" "" "CVE-2022-38694_unlock_bootloader"

echo ""
echo "[7/7] Verification"
echo -n "ADB (Android Debug Bridge — USB device communication) version: "
adb --version 2>&1 | head -n1 || true

echo -n "Fastboot (Android Fastboot — bootloader flashing mode) version: "
fastboot --version 2>&1 | head -n1 || true

echo -n "DTC (Device Tree Compiler — DTB/DTS tool) version: "
dtc --version 2>&1 | head -n1 || true

echo -n "extract-dtb (Python DTB extractor) version: "
python3 -c "import extract_dtb; print('OK')" 2>/dev/null || echo "(MISSING - run: pip3 install --user extract-dtb)"

echo -n "simg2img (Android sparse image converter) path: "
command -v simg2img || true

echo -n "lpunpack (Logical Partitions unpack tool) path: "
command -v lpunpack || echo "(missing; python fallback still possible)"

echo -n "lpmake (Logical Partitions image builder) path: "
command -v lpmake || echo "(missing; not fatal for extraction)"

echo -n "pmbootstrap (postmarketOS build tool) version: "
pmbootstrap --version 2>/dev/null || echo "(pmbootstrap installed; restart shell if needed)"

echo -n "spd_dump (Spreadtrum/Unisoc flash tool) path: "
command -v spd_dump || echo "(missing; check tools/spreadtrum_flash)"

echo ""
echo "=== Setup complete ==="
echo ""
echo "IMPORTANT: Run all scripts inside the distrobox container:"
echo "  distrobox enter teclast-dev"
echo "  bash scripts/run_all.sh"
echo ""
echo "If PATH changes were added, restart the shell (or run: exec \$SHELL -l)."

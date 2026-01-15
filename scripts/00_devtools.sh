#!/usr/bin/env bash
set -euo pipefail

# Teclast P20HD postmarketOS port - development environment bootstrap
# Idempotent: safe to run multiple times.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo "=== Teclast P20HD Development Environment Setup ==="
echo "Project directory: $PROJECT_DIR"

echo "[1/7] Updating system packages..."
sudo apt update
sudo apt upgrade -y

echo "[2/7] Installing base development tools..."
sudo apt install -y \
  git curl wget vim nano \
  build-essential \
  bc bison flex \
  libssl-dev libncurses-dev libelf-dev \
  python3 python3-pip python3-venv \
  p7zip-full unrar \
  tree jq \
  e2fsprogs \
  file \
  rsync

echo "[3/7] Installing Android tools..."
sudo apt install -y \
  android-tools-adb \
  android-tools-fastboot \
  android-sdk-libsparse-utils

echo "[4/7] Installing boot/kernel analysis tools..."
sudo apt install -y \
  device-tree-compiler \
  u-boot-tools \
  abootimg \
  binwalk \
  cpio gzip bzip2 lz4 xz-utils \
  unzip zip

echo "[5/7] Installing cross compilation tools..."
sudo apt install -y \
  gcc-aarch64-linux-gnu \
  g++-aarch64-linux-gnu

echo "[6/7] Installing Python tools..."
python3 -m pip install --user --upgrade pip
python3 -m pip install --user --upgrade \
  extract-dtb \
  pycryptodome

# Ensure ~/.local/bin is available
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "==> Creating workspace structure..."
mkdir -p "$PROJECT_DIR"/{firmware,backup,extracted,modified,output,scripts,tools,device-info}

# -----------------------------------------------------------------------------#
# AIK (Android Image Kitchen — boot image unpack/repack toolkit)
# -----------------------------------------------------------------------------#
AIK_REPO="https://github.com/ndrancs/AIK-Linux-x32-x64.git"

echo ""
echo "==> Setting up AIK (Android Image Kitchen — boot image unpack/repack toolkit)..."
if [[ ! -d "$PROJECT_DIR/AIK/.git" ]]; then
  rm -rf "$PROJECT_DIR/AIK"
  git clone "$AIK_REPO" "$PROJECT_DIR/AIK"
else
  ( cd "$PROJECT_DIR/AIK" && git pull )
fi
chmod +x "$PROJECT_DIR"/AIK/*.sh || true

# Patch stray 'return' if present (harmless but noisy)
if grep -qE '^[[:space:]]*return[[:space:]]*$' "$PROJECT_DIR/AIK/unpackimg_x64.sh" 2>/dev/null; then
  echo "==> Patching AIK unpackimg_x64.sh: replacing stray 'return' with 'exit 0'..."
  sed -i -E 's/^[[:space:]]*return[[:space:]]*$/exit 0/' "$PROJECT_DIR/AIK/unpackimg_x64.sh"
fi

# -----------------------------------------------------------------------------#
# pacextractor (Spreadtrum/UNISOC .pac extractor)
# -----------------------------------------------------------------------------#
echo ""
echo "==> Setting up pacextractor (Spreadtrum/UNISOC .pac extractor)..."
if [[ ! -d "$PROJECT_DIR/tools/pacextractor/.git" ]]; then
  git clone https://github.com/divinebird/pacextractor.git "$PROJECT_DIR/tools/pacextractor"
else
  ( cd "$PROJECT_DIR/tools/pacextractor" && git pull )
fi
( cd "$PROJECT_DIR/tools/pacextractor" && make )

# -----------------------------------------------------------------------------#
# partition_tools (lpunpack/lpmake — Android Logical Partitions utilities)
# -----------------------------------------------------------------------------#
echo ""
echo "==> Ensuring lpunpack/lpmake (Logical Partitions tools) are available..."

need_tools=0
for t in lpunpack lpmake; do
  if ! command -v "$t" >/dev/null 2>&1; then
    need_tools=1
  fi
done

if [[ "$need_tools" -eq 1 ]]; then
  echo "[*] lpunpack/lpmake not found in PATH. Installing local copies into ~/.local/bin ..."

  mkdir -p "$PROJECT_DIR/tools"
  mkdir -p "$HOME/.local/bin"

  # ---- Option A: try to build from LonelyFool (source) ----
  LF_REPO="https://github.com/LonelyFool/lpunpack_and_lpmake.git"
  LF_DIR="$PROJECT_DIR/tools/lpunpack_and_lpmake"

  echo "[*] Attempting source-based setup: $LF_REPO"
  if [[ ! -d "$LF_DIR/.git" ]]; then
    rm -rf "$LF_DIR"
    git clone "$LF_REPO" "$LF_DIR" || true
  else
    ( cd "$LF_DIR" && git pull ) || true
  fi

  # Try build scripts if present
  if [[ -d "$LF_DIR" ]]; then
    if [[ -x "$LF_DIR/make.sh" ]]; then
      echo "[*] Running LonelyFool make.sh ..."
      ( cd "$LF_DIR" && bash ./make.sh ) || true
    elif [[ -f "$LF_DIR/Makefile" ]]; then
      echo "[*] Running make ..."
      ( cd "$LF_DIR" && make ) || true
    fi
  fi

  # Try to locate built binaries
  copied_any=0
  for bin in lpunpack lpmake lpdump lpflash; do
    src="$(find "$LF_DIR" -maxdepth 5 -type f -name "$bin" -perm -111 2>/dev/null | head -n 1 || true)"
    if [[ -n "$src" ]]; then
      echo "[*] Installing $bin from source build: $src"
      install -m 0755 "$src" "$HOME/.local/bin/$bin"
      copied_any=1
    fi
  done

  # ---- Option B: fallback to prebuilt static tools ----
  if [[ "$copied_any" -eq 0 ]]; then
    echo "[*] Source build did not yield binaries. Falling back to prebuilt tools..."

    PREBUILT_REPO="https://github.com/Rprop/aosp15_partition_tools.git"
    PREBUILT_DIR="$PROJECT_DIR/tools/aosp15_partition_tools"

    if [[ ! -d "$PREBUILT_DIR/.git" ]]; then
      rm -rf "$PREBUILT_DIR"
      git clone "$PREBUILT_REPO" "$PREBUILT_DIR"
    else
      ( cd "$PREBUILT_DIR" && git pull )
    fi

    if [[ -d "$PREBUILT_DIR/linux_glibc_x86_64" ]]; then
      echo "[*] Installing prebuilt partition_tools into ~/.local/bin ..."
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

# -----------------------------------------------------------------------------#
# pmbootstrap (postmarketOS build tool) + pmaports (ports tree reference)
# -----------------------------------------------------------------------------#
echo ""
echo "==> Setting up pmbootstrap (postmarketOS build tool)..."
if [[ ! -d "$PROJECT_DIR/pmbootstrap/.git" ]]; then
  git clone https://gitlab.com/postmarketOS/pmbootstrap.git "$PROJECT_DIR/pmbootstrap"
else
  ( cd "$PROJECT_DIR/pmbootstrap" && git pull )
fi
python3 -m pip install --user --upgrade "$PROJECT_DIR/pmbootstrap"

echo ""
echo "==> Setting up pmaports (postmarketOS ports tree reference)..."
if [[ ! -d "$PROJECT_DIR/pmaports/.git" ]]; then
  git clone --depth=1 https://gitlab.com/postmarketOS/pmaports.git "$PROJECT_DIR/pmaports"
else
  ( cd "$PROJECT_DIR/pmaports" && git pull )
fi

echo ""
echo "[7/7] Verification"
echo -n "ADB (Android Debug Bridge — USB device communication) version: "
adb --version 2>&1 | head -n1 || true

echo -n "Fastboot (Android Fastboot — bootloader flashing mode) version: "
fastboot --version 2>&1 | head -n1 || true

echo -n "DTC (Device Tree Compiler — DTB/DTS tool) version: "
dtc --version 2>&1 | head -n1 || true

echo -n "simg2img (Android sparse image converter) path: "
command -v simg2img || true

echo -n "lpunpack (Logical Partitions unpack tool) path: "
command -v lpunpack || echo "(missing; python fallback still possible)"

echo -n "lpmake (Logical Partitions image builder) path: "
command -v lpmake || echo "(missing; not fatal for extraction)"

echo -n "pmbootstrap (postmarketOS build tool) version: "
pmbootstrap --version 2>/dev/null || echo "(pmbootstrap installed; restart shell if needed)"

echo ""
echo "=== Setup complete ==="
echo "Next recommended interactive shell:"
echo "  distrobox enter teclast-dev -- bash -l"

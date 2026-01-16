# Droidian Porting Guide for Teclast P20HD

This document outlines the steps to port Droidian to the Teclast P20HD tablet (Unisoc SC9863A).

## Device Information

| Property | Value |
|----------|-------|
| Device | Teclast P20HD |
| Codename | s9863a1h10 / N6H1 |
| SoC | Unisoc SC9863A (Sharkl3) |
| CPU | Octa-core Cortex-A55 (4x1.6GHz + 4x1.2GHz) |
| GPU | PowerVR GE8322 / IMG8322 |
| RAM | 4GB |
| Android | 10 (API 29) |
| Kernel | 4.14.133 |
| Treble | Yes (GSI compatible) |

## Prerequisites

- [x] Bootloader unlocked (completed via `12_unlock_bootloader.sh`)
- [x] Boot parameters extracted (see `extracted/bootimg_info/`)
- [x] Device tree extracted (see `extracted/dtb_from_bootimg/`)
- [x] Vendor blobs identified (see `extracted/vendor_blobs/`)
- [ ] Kernel source obtained
- [ ] Halium patches applied
- [ ] Kernel compiled with Droidian config

---

## Step 1: Obtain Kernel Source

The kernel source is **critical**. Options:

### Option A: Samsung A03 Core Kernel (Recommended)

Samsung Galaxy A03 Core (SM-A032) uses the same SC9863A SoC.

```bash
# Clone IverCoder's Droidian branch
git clone -b droidian https://github.com/IverCoder/linux-android-samsung-a03.git
cd linux-android-samsung-a03
```

### Option B: Official Samsung Open Source

1. Visit https://opensource.samsung.com
2. Search for "SM-A032" or "A03 Core"
3. Download kernel source package

### Option C: Request from Teclast

Email Teclast support requesting GPL kernel source for P20HD (N6H1).

---

## Step 2: Set Up Build Environment

### Install Dependencies (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y \
    build-essential bc bison flex libssl-dev \
    device-tree-compiler python3 python-is-python3 \
    git wget curl unzip \
    android-sdk-libsparse-utils \
    clang llvm lld
```

### Get Android Toolchain (matches original build)

```bash
# Clang r383902 (LLVM 9.0.3) - used in original kernel
mkdir -p ~/toolchains
cd ~/toolchains

# GCC
git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9

# Clang (use NDK or AOSP clang)
wget https://dl.google.com/android/repository/android-ndk-r21e-linux-x86_64.zip
unzip android-ndk-r21e-linux-x86_64.zip
```

---

## Step 3: Prepare Kernel for Droidian

### Apply Halium/Hybris Patches

```bash
cd linux-android-samsung-a03

# Clone hybris-patches
git clone https://github.com/halium/hybris-patches.git

# Apply patches
hybris-patches/apply-patches.sh --mb
```

### Add Device to fixup-mountpoints

Edit `hybris-boot/fixup-mountpoints` and add the Teclast P20HD entry.
See `droidian/kernel/fixup-mountpoints.patch` for the template.

**Important:** Get actual partition numbers first:

```bash
adb shell ls -la /dev/block/platform/soc/soc:ap-ahb/20600000.sdio/by-name/
adb shell cat /proc/partitions
```

### Configure Kernel

```bash
# Copy or create defconfig
# If adapting Samsung A03 kernel, start with their defconfig
cp arch/arm64/configs/a03_defconfig arch/arm64/configs/s9863a1h10_defconfig

# Verify required configs with mer-kernel-check
scripts/kconfig/merge_config.sh -m arch/arm64/configs/s9863a1h10_defconfig \
    droidian/droidian.config

# Build config
make ARCH=arm64 s9863a1h10_defconfig
```

### Required Kernel Configs

Verify these are enabled (use `mer-kernel-check`):

```
CONFIG_DEVTMPFS=y
CONFIG_VT=y
CONFIG_NAMESPACES=y
CONFIG_MODULES=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
CONFIG_ANDROID_BINDERFS=y  # if using binderfs
```

---

## Step 4: Create Debian Packaging

### Copy kernel-info.mk

```bash
mkdir -p debian
cp /path/to/this/repo/droidian/kernel/kernel-info.mk debian/
```

### Verify/Adjust Boot Parameters

The `kernel-info.mk` contains parameters extracted from stock boot.img:

| Parameter | Value | Source |
|-----------|-------|--------|
| KERNEL_BOOTIMAGE_VERSION | 2 | boot header |
| KERNEL_BOOTIMAGE_PAGE_SIZE | 2048 | boot header |
| KERNEL_BOOTIMAGE_BASE_OFFSET | 0x00000000 | boot header |
| KERNEL_BOOTIMAGE_KERNEL_OFFSET | 0x00008000 | boot header |
| KERNEL_BOOTIMAGE_INITRAMFS_OFFSET | 0x05400000 | boot header |
| KERNEL_BOOTIMAGE_TAGS_OFFSET | 0x00000100 | boot header |
| KERNEL_BOOTIMAGE_CMDLINE | console=ttyS1,115200n8 | boot header |

---

## Step 5: Adapt Device Tree

The P20HD uses different hardware than Samsung A03. Key differences:

### Display Panel

- **P20HD**: ILI9881C (`lcd_s9863a_fx_boe_9881c`)
- Panel init sequences in: `extracted/dtb_from_bootimg/01_dtbdump_,Unisoc_SC9863a.dts`

### Touch Controller

- **P20HD**: FocalTech FT5436 at I2C 0x38
- Driver: `focaltech,FT5436`
- Firmware: `extracted/vendor_blobs/firmware/focaltech-FT5x46.bin`

### Adaptation Required

1. Copy panel DTS node from extracted DTB
2. Verify touch controller compatible string
3. Check WiFi/BT firmware paths

---

## Step 6: Build Kernel

```bash
# Set up environment
export ARCH=arm64
export CROSS_COMPILE=~/toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
export CC=~/toolchains/android-ndk-r21e/toolchains/llvm/prebuilt/linux-x86_64/bin/clang

# Build
make -j$(nproc) Image.gz dtbs

# Or use Droidian build system
./build_kernel.sh
```

---

## Step 7: Create Droidian Boot Image

### Using mkbootimg

```bash
mkbootimg \
    --kernel arch/arm64/boot/Image.gz-dtb \
    --ramdisk halium-boot-ramdisk.img \
    --base 0x00000000 \
    --pagesize 2048 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x05400000 \
    --tags_offset 0x00000100 \
    --cmdline "console=ttyS1,115200n8 console=tty0 droidian.lvm.prefer" \
    --header_version 2 \
    --output droidian-boot.img
```

---

## Step 8: Test Boot

### RAM Boot (Safe - No Flash)

```bash
# Reboot to fastboot
adb reboot bootloader

# Boot from RAM (does not modify device)
fastboot boot droidian-boot.img
```

### Debug via Serial Console

The device has serial console on `ttyS1` at 115200 baud.
If you have UART access, connect to see boot logs.

### Debug via Telnet (if SSH fails)

Droidian's initramfs provides telnet on port 23 during early boot:

```bash
# After boot attempt, if device gets IP
telnet <device_ip> 23
```

---

## Step 9: Create Adaptation Package

The `droidian/adaptation/` directory contains the skeleton.

### Finalize and Build

```bash
cd droidian/adaptation
dpkg-buildpackage -us -uc -b
```

---

## Directory Structure

```
droidian/
├── kernel/
│   ├── kernel-info.mk           # Boot parameters for Droidian build
│   └── fixup-mountpoints.patch  # Halium mountpoint fixes
├── adaptation/
│   ├── debian/
│   │   ├── control              # Package metadata
│   │   ├── rules                # Build rules
│   │   └── changelog            # Version history
│   └── sparse/
│       └── etc/
│           └── deviceinfo/
│               └── s9863a1h10.conf  # Device properties
└── PORTING_GUIDE.md             # This file
```

---

## Extracted Assets (Useful for Porting)

| Asset | Location | Use |
|-------|----------|-----|
| Boot parameters | `extracted/bootimg_info/` | kernel-info.mk values |
| Device tree | `extracted/dtb_from_bootimg/*.dts` | Panel/touch config |
| fstab | `extracted/ramdisk_init/fstab/` | Partition layout |
| GPU firmware | `extracted/vendor_blobs/firmware/rgx.fw.*` | PowerVR blobs |
| Touch firmware | `extracted/vendor_blobs/firmware/focaltech-*.bin` | FT5436 firmware |
| VINTF manifest | `extracted/vendor_blobs/etc/vintf/` | HAL versions |

---

## Resources

- [Droidian Porting Guide](https://github.com/droidian/porting-guide)
- [Droidian Documentation](https://docs.droidian.org/)
- [Samsung A03 Kernel (Droidian)](https://github.com/IverCoder/linux-android-samsung-a03)
- [Halium Documentation](https://docs.halium.org/)
- [Droidian Devices Organization](https://github.com/droidian-devices)

---

## Status Checklist

- [x] Bootloader unlocked
- [x] Boot parameters extracted
- [x] Device tree extracted
- [x] Vendor blobs cataloged
- [x] kernel-info.mk created
- [x] Adaptation skeleton created
- [ ] Kernel source obtained
- [ ] Halium patches applied
- [ ] Kernel compiled
- [ ] Boot tested (RAM boot)
- [ ] Display working
- [ ] Touch working
- [ ] WiFi working
- [ ] GPU acceleration working
- [ ] Full system functional

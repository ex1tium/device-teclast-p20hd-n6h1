########################################################################
# Droidian Kernel Configuration for Teclast P20HD (N6H1)
########################################################################
# SoC: Unisoc SC9863A (Sharkl3)
# Based on IverCoder/linux-android-samsung-a03 (droidian branch)

########################################################################
# Kernel settings
########################################################################

# Kernel variant: 'android' for downstream kernels
VARIANT = android

# Kernel base version (from source Makefile)
KERNEL_BASE_VERSION = 4.14-0

# Kernel cmdline
KERNEL_BOOTIMAGE_CMDLINE = console=ttyS1,115200n8 androidboot.hardware=s9863a1h10

# Device vendor/model slugs (used in package names)
DEVICE_VENDOR = teclast
DEVICE_MODEL = p20hd
DEVICE_FULL_NAME = Teclast P20HD

# Defconfig to use
KERNEL_DEFCONFIG = teclast/p20hd_defconfig

# Whether to use configuration fragments
KERNEL_CONFIG_USE_FRAGMENTS = 0

# Whether to use diffconfig
KERNEL_CONFIG_USE_DIFFCONFIG = 0

########################################################################
# Device tree configuration
########################################################################

# Include DTB with kernel image
KERNEL_IMAGE_WITH_DTB = 1

# Path to DTB (auto-detected if not specified)
KERNEL_IMAGE_DTB = arch/arm64/boot/dts/sprd/sp9863a.dtb

# Include DTB overlay
KERNEL_IMAGE_WITH_DTB_OVERLAY = 1

# Path to DTBO
KERNEL_IMAGE_DTB_OVERLAY = arch/arm64/boot/dts/sprd/sp9863a-p20hd-overlay.dtbo

# Don't include DTBO in kernel image (ship separately)
KERNEL_IMAGE_WITH_DTB_OVERLAY_IN_KERNEL = 0

########################################################################
# Boot image parameters (from stock boot.img)
########################################################################

# Boot image header version (Android 10 = version 2)
KERNEL_BOOTIMAGE_VERSION = 2

# Page size
KERNEL_BOOTIMAGE_PAGE_SIZE = 2048

# Memory offsets
KERNEL_BOOTIMAGE_BASE_OFFSET = 0x00000000
KERNEL_BOOTIMAGE_KERNEL_OFFSET = 0x00008000
KERNEL_BOOTIMAGE_INITRAMFS_OFFSET = 0x05400000
KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET = 0x00f00000
KERNEL_BOOTIMAGE_TAGS_OFFSET = 0x00000100
KERNEL_BOOTIMAGE_DTB_OFFSET = 0x01f00000

# Initramfs compression
KERNEL_INITRAMFS_COMPRESSION = gz

########################################################################
# Android verified boot
########################################################################

# Build vbmeta.img (disables verified boot)
DEVICE_VBMETA_REQUIRED = 1

# Not a Samsung device
DEVICE_VBMETA_IS_SAMSUNG = 0

########################################################################
# Flashing configuration
########################################################################

# Enable kernel flashing on package upgrades
FLASH_ENABLED = 1

# Not an A-only device (has separate system/vendor)
FLASH_IS_AONLY = 0

# Not a legacy device
FLASH_IS_LEGACY_DEVICE = 0

# Not an Exynos device
FLASH_IS_EXYNOS = 0

# Use fastboot for flashing
FLASH_USE_TELNET = 0

# Device identification
FLASH_INFO_MANUFACTURER = Teclast
FLASH_INFO_MODEL = P20HD_EEA
FLASH_INFO_CPU = Unisoc SC9863a
FLASH_INFO_DEVICE_IDS = P20HD P20HD_EEA N6H1 s9863a1h10

########################################################################
# Build configuration
########################################################################

# Cross-compile for ARM64
BUILD_CROSS = 1

# Android toolchain triplet
BUILD_TRIPLET = aarch64-linux-android-

# Clang triplet
BUILD_CLANG_TRIPLET = aarch64-linux-gnu-

# Use clang compiler
BUILD_CC = clang

# Don't use full LLVM (not needed for 4.14 kernel)
BUILD_LLVM = 0

# Include modules
BUILD_SKIP_MODULES = 0

# Clang path (Android LLVM 6.0)
BUILD_PATH = /usr/lib/llvm-android-6.0-4691093/bin

# Build dependencies
DEB_TOOLCHAIN = linux-initramfs-halium-generic:arm64, binutils-aarch64-linux-gnu, clang-android-6.0-4691093, gcc-4.9-aarch64-linux-android, g++-4.9-aarch64-linux-android, libgcc-4.9-dev-aarch64-linux-android-cross

# Build/target architectures
DEB_BUILD_ON = amd64
DEB_BUILD_FOR = arm64
KERNEL_ARCH = arm64

# Kernel build target
KERNEL_BUILD_TARGET = Image.gz

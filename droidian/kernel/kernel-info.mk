# Droidian Kernel Configuration for Teclast P20HD (s9863a1h10)
# Generated from extracted boot.img parameters
#
# This file is used by droidian kernel build system
# Place in debian/kernel-info.mk of your kernel repository

########################################################################
# Kernel base version
########################################################################
# Extract from kernel source Makefile (VERSION.PATCHLEVEL.SUBLEVEL)
KERNEL_BASE_VERSION = 4.14.133

########################################################################
# Device kernel configuration
########################################################################
# Path to defconfig relative to kernel source root
# TODO: Obtain from Samsung A03 Core kernel source and adapt
KERNEL_DEFCONFIG = s9863a1h10_defconfig

########################################################################
# Device tree configuration
########################################################################
# Whether DTB is included in kernel image (1 = yes)
KERNEL_IMAGE_WITH_DTB = 1

# Path to DTB file (relative to kernel source)
# TODO: Verify exact path in kernel source
KERNEL_IMAGE_DTB = arch/arm64/boot/dts/sprd/sp9863a-1h10.dtb

# Device tree overlay support (1 = yes, 0 = no)
KERNEL_IMAGE_DTB_OVERLAY = 1

# Use configuration fragments from droidian/ directory
KERNEL_CONFIG_USE_FRAGMENTS = 1

########################################################################
# Boot image parameters (extracted from stock boot.img)
########################################################################
# Boot image header version (0=Android 8, 1=Android 9, 2=Android 10/11, 3=GKI)
KERNEL_BOOTIMAGE_VERSION = 2

# Page size in bytes
KERNEL_BOOTIMAGE_PAGE_SIZE = 2048

# Base address
KERNEL_BOOTIMAGE_BASE_OFFSET = 0x00000000

# Kernel load offset
KERNEL_BOOTIMAGE_KERNEL_OFFSET = 0x00008000

# Ramdisk load offset
KERNEL_BOOTIMAGE_INITRAMFS_OFFSET = 0x05400000

# Second stage bootloader offset (not used on this device)
KERNEL_BOOTIMAGE_SECONDIMAGE_OFFSET = 0x00f00000

# Tags offset
KERNEL_BOOTIMAGE_TAGS_OFFSET = 0x00000100

# DTB offset (for header version 2+)
# TODO: Extract from boot.img if present
KERNEL_BOOTIMAGE_DTB_OFFSET = 0x01f00000

########################################################################
# Kernel command line
########################################################################
# Original: console=ttyS1,115200n8 buildvariant=user
# Droidian additions: droidian.lvm.prefer console=tty0
KERNEL_BOOTIMAGE_CMDLINE = console=ttyS1,115200n8 console=tty0 droidian.lvm.prefer

########################################################################
# Compiler configuration
########################################################################
# Use clang for Android 9+ kernels (matches original build)
BUILD_CC = clang

# Clang version used in original build: r353983c (LLVM 9.0.3)
# For Droidian, use system clang or specify Android clang path

########################################################################
# Additional notes
########################################################################
# SoC: Unisoc SC9863A (Sharkl3)
# GPU: PowerVR GE8322 / IMG8322
# Original kernel built: Sat Oct 23 15:42:51 CST 2021
# Original compiler: Android clang 9.0.3 (r353983c)
#
# Kernel source options:
# 1. Samsung A03 Core kernel (same SoC):
#    https://github.com/IverCoder/linux-android-samsung-a03
# 2. Samsung kernel from opensource.samsung.com (SM-A032)
# 3. Teclast may release source (check their website)

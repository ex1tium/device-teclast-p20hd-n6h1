# Phase 3: First Boot - Droidian Testing Guide

This document describes how to test the first boot of Droidian on the Teclast P20HD tablet.

## Prerequisites

- **Bootloader unlocked** (already completed)
- **ADB/Fastboot working** (distrobox enter teclast-dev)
- **Stock backup available** in `backup/` directory
- **SPD Flash Tool ready** (see [Recovery Guide](#recovery-from-brick-spd-download-mode) below)

> **CRITICAL WARNING**: This device has NO hardware button combination to enter fastboot mode. If flashing fails and the device won't boot, you MUST use SPD Download Mode recovery. **Always have recovery tools ready before flashing!**

## Output Files

| File | Size | Purpose |
|------|------|---------|
| `out/boot-droidian.img` | 14.6 MB | Kernel + Droidian initramfs + DTB |
| `out/vbmeta-disabled.img` | 1.0 MB | AVB disabled (verification off) |

## Boot Image Details

```
kernel:         kernel/linux-teclast-p20hd/arch/arm64/boot/Image.gz (9.1 MB)
ramdisk:        droidian/initramfs/initrd.img-touch-arm64 (5.4 MB)
dtb:            kernel/linux-teclast-p20hd/arch/arm64/boot/dts/sprd/sp9863a.dtb (89 KB)
cmdline:        console=ttyS1,115200n8 console=tty0 droidian.lvm.prefer
header_version: 2
page_size:      2048
base:           0x00000000
kernel_offset:  0x00008000
ramdisk_offset: 0x05400000
tags_offset:    0x00000100
```

---

## Testing Procedure

### Step 1: Enter Fastboot Mode

```bash
# From Android (ONLY way to enter fastboot on this device):
adb reboot bootloader
```

> **Note**: There is NO button combination to enter fastboot on the P20HD. You must use `adb reboot bootloader` from a working Android system.

Verify device is in fastboot:
```bash
distrobox enter teclast-dev -- fastboot devices
```

### Step 2: RAM Boot Test (Non-destructive)

> **⚠️ NOT SUPPORTED ON THIS DEVICE**: The Unisoc bootloader on the P20HD does not support `fastboot boot` (RAM boot). Attempting this command returns a **protocol error**. You must flash the boot image directly to test.

~~**This does NOT flash anything - safe to test!**~~

```bash
cd /var/home/ex1tium/projects/device-teclast-p20hd-n6h1

# Boot directly from RAM - DOES NOT WORK on P20HD
distrobox enter teclast-dev -- fastboot boot out/boot-droidian.img
# Returns: FAILED (status read failed (Protocol error))
```

**Since RAM boot is not available, you must flash directly (Step 4) to test. This makes testing riskier — always have SPD recovery tools ready!**

### Step 3: Check for Telnet Access (Initramfs Debug)

If the device boots to initramfs but can't find rootfs, it drops to a debug shell accessible via USB networking:

```bash
# Wait ~30 seconds after boot
# Check if USB networking interface appears
ip link show

# Try to connect (common initramfs debug IP)
telnet 192.168.2.15 23
# or
ssh root@192.168.2.15
```

### Step 4: Serial Console Debugging (Optional)

If you have a USB-UART adapter connected to the device's UART pins:

```bash
# ttyS1 is the debug console at 115200 baud
screen /dev/ttyUSB0 115200
```

---

## Flashing Procedure

> **Note**: Since RAM boot (`fastboot boot`) is not supported on this device, flashing is the only way to test custom boot images. **Always have SPD recovery tools ready before flashing!**

### Flash vbmeta First (Disable AVB)

```bash
# CRITICAL: Flash disabled vbmeta to allow custom boot
distrobox enter teclast-dev -- fastboot flash vbmeta out/vbmeta-disabled.img
```

**Unisoc SC9863A Note:** vbmeta MUST be exactly 1 MiB (1,048,576 bytes). The generated image is already padded correctly.

### Flash Boot Image

```bash
distrobox enter teclast-dev -- fastboot flash boot out/boot-droidian.img
```

### Reboot

```bash
distrobox enter teclast-dev -- fastboot reboot
```

---

## Recovery from Brick (SPD Download Mode)

> **This is the ONLY recovery method if the device won't boot to Android or fastboot.**

### Understanding the Problem

The Unisoc SC9863A bootloader verifies boot image signatures against vbmeta chain descriptors. If verification fails, the bootloader halts at the splash screen showing:
```
TECLAST
INFO: LOCK FLAG IS: UNLOCK!!!
```

The device enters SPD Download Mode (BROM) automatically when stuck, detectable as USB device `1782:4d00`.

### Detection

```bash
# Check if device is in SPD mode
lsusb | grep "1782:4d00"
# Output: Bus 001 Device XXX: ID 1782:4d00 Spreadtrum Communications Inc.
```

### Recovery Options

#### Option 1: Linux (spd_dump) - Partial Recovery

The `spd_dump` tool can flash individual partitions but struggles with large partitions (super.img is 3GB).

**Setup:**
```bash
# Clone and build (or run scripts/00_devtools.sh)
cd tools
git clone https://github.com/ilyakurdyukov/spreadtrum_flash.git
cd spreadtrum_flash && make
```

**Flash stock boot image:**
```bash
# Power cycle: hold power 30+ sec, unplug USB, wait 5 sec
# Then run this and plug USB back in:
echo "yes" | sudo ./tools/spreadtrum_flash/spd_dump --wait 180 \
    fdl firmware/extracted_pac/fdl1-sign.bin 0x5000 \
    fdl firmware/extracted_pac/fdl2-sign.bin 0x9efffe00 \
    write_part boot firmware/extracted_pac/boot.img \
    reset
```

**Flash vbmeta partitions:**
```bash
# Repeat power cycle for each partition
echo "yes" | sudo ./tools/spreadtrum_flash/spd_dump --wait 180 \
    fdl firmware/extracted_pac/fdl1-sign.bin 0x5000 \
    fdl firmware/extracted_pac/fdl2-sign.bin 0x9efffe00 \
    write_part vbmeta firmware/extracted_pac/vbmeta-sign.img \
    reset
```

**FDL Base Addresses (from s9863a1h10.xml):**
- FDL1: `0x5000`
- FDL2: `0x9EFFFE00`

#### Option 2: Windows SPD Flash Tool - Full Recovery (Recommended)

For full system restore including the 3GB super partition, use Windows SPD Flash Tool:

1. **Download SPD Flash Tool** from [spdflashtool.com](https://spdflashtool.com/)
2. **Install SPD USB drivers**
3. **Extract stock firmware**: `firmware/P20HD(N6H1)_Android 10.0_EEA_V1.07_SZ.rar`
4. **Load the PAC file** in SPD Flash Tool
5. **Power cycle device** (hold power 30+ sec until screen goes black)
6. **Click "Start Downloading"** in SPD Flash Tool
7. **Plug in USB cable** - tool will detect device and flash

### Recovery Files Available

| File | Location | Purpose |
|------|----------|---------|
| Stock boot | `firmware/extracted_pac/boot.img` | 35 MB boot partition |
| Stock vbmeta | `firmware/extracted_pac/vbmeta-sign.img` | 1 MB AVB metadata |
| Stock super | `firmware/extracted_pac/super.img` | 3 GB system/vendor/product |
| Stock recovery | `firmware/extracted_pac/recovery.img` | 40 MB recovery partition |
| FDL1 | `firmware/extracted_pac/fdl1-sign.bin` | First-stage loader |
| FDL2 | `firmware/extracted_pac/fdl2-sign.bin` | Second-stage loader |
| Full firmware | `firmware/P20HD(N6H1)_Android 10.0_EEA_V1.07_SZ.rar` | Complete PAC file |

---

## Troubleshooting

### "writing vbmeta" hangs forever

This is a known Unisoc issue. The vbmeta image MUST be exactly 1 MiB. Verify:
```bash
stat -c%s out/vbmeta-disabled.img
# Should output: 1048576
```

### Device stuck at splash screen (not bootlooping)

This indicates boot image signature verification failure. The bootloader halts rather than booting.

**Solution**: Use SPD Download Mode recovery (see above).

### Device bootlooping

The boot image loads but crashes. This could be:
- Kernel panic (check serial console)
- Missing/corrupted super partition
- AVB verification mismatch

**Solution**:
1. Try SPD recovery to flash stock boot + vbmeta
2. If still bootlooping, flash the full super partition via Windows SPD Flash Tool

### Cannot enter fastboot mode

**This device has NO button combination for fastboot.** The only way to enter fastboot is:
```bash
adb reboot bootloader
```

If Android won't boot, you cannot enter fastboot. Use SPD Download Mode recovery instead.

### spd_dump times out or gives checksum errors

- Power cycle the device completely (30+ seconds power hold)
- Unplug USB before starting spd_dump
- Try a different USB port/cable
- The device may need multiple attempts to connect cleanly

### spd_dump fails on large partitions (super.img)

The Linux spd_dump tool has reliability issues with large transfers. The 3GB super partition typically fails around 256MB.

**Solution**: Use Windows SPD Flash Tool for full system restore.

---

## Partition Reference

| Partition | Device | Size |
|-----------|--------|------|
| boot | /dev/block/mmcblk0p28 | 35 MB |
| dtbo | /dev/block/mmcblk0p29 | 8 MB |
| vbmeta | /dev/block/mmcblk0p34 | 1 MB |
| vbmeta_bak | /dev/block/mmcblk0p35 | 1 MB |
| vbmeta_system | /dev/block/mmcblk0p38 | 1 MB |
| vbmeta_vendor | /dev/block/mmcblk0p39 | 1 MB |
| userdata | /dev/block/mmcblk0p40 | remaining |
| super | /dev/block/mmcblk0p30 | 4100 MB |
| recovery | /dev/block/mmcblk0p4 | 40 MB |

---

## Next Steps After Successful Boot

1. **Phase 4: Display Bringup** - Verify ILI9881C panel driver loads
2. **Phase 5: Touch Input** - Test FocalTech FT5436 touch
3. **Phase 6: Userspace** - Flash Droidian rootfs to userdata

---

## Files Checklist

Before testing, verify all files exist:

```bash
ls -la out/boot-droidian.img out/vbmeta-disabled.img
ls -la backup/boot-stock.img backup/vbmeta-sign.img
ls -la firmware/extracted_pac/fdl1-sign.bin firmware/extracted_pac/fdl2-sign.bin
```

**Always have stock backups AND recovery tools ready before flashing!**

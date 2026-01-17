# Teclast P20HD (N6H1 / Unisoc SC9863A) — Droidian / Linux Bringup Workspace

This repository contains a **bringup extraction pipeline** and **Droidian porting workspace** for the **Teclast P20HD EEA** tablet (**N6H1**, **Unisoc SC9863A / s9863a1h10**).

---

## ⚠️ Critical Finding: Unisoc Secure Boot

**Unlocking the bootloader is NOT enough to flash custom images on Unisoc devices.**

Even with an unlocked bootloader, the Unisoc SC9863A **still enforces cryptographic signature verification** on boot, vbmeta, and other partitions. Simply flashing an unsigned boot image will result in a **bootloop or boot failure**.

### Solution: AVB-Signed Images

Custom boot images must be:
1. **Signed with a matching private key**
2. **Accompanied by a custom vbmeta** that references the signing key
3. **vbmeta must be exactly 1 MiB** (Unisoc-specific requirement)

We have confirmed that the **leaked Hovatek `rsa4096_vbmeta.pem`** key matches the P20HD's vbmeta signer, enabling us to create properly signed images.

**See [docs/UNISOC_AVB_SIGNING.md](docs/UNISOC_AVB_SIGNING.md) for complete signing documentation.**

---

## Current Focus: Droidian

The project is actively working toward a **Droidian** port (Debian-based mobile Linux using Android HAL via libhybris). The extraction pipeline provides the foundation for kernel building and device adaptation.

| Component | Status |
|-----------|--------|
| Bootloader unlock | **Done** (Unisoc signature method) |
| Boot parameters extracted | **Done** |
| Device tree extracted | **Done** |
| Vendor blobs cataloged | **Done** |
| Droidian adaptation skeleton | **Done** |
| Kernel source | **Done** (Samsung A03 Core kernel, p20hd branch) |
| Kernel compilation | **Done** (builds successfully) |
| First boot test | **In Progress** (device recovery needed) |

### Current Status

The kernel has been compiled successfully and AVB-signed boot images have been generated. First boot test with unsigned images resulted in bootloop due to AVB signature verification (see critical finding above).

**Completed:**
- ✅ Kernel compiled (Samsung A03 Core kernel, p20hd branch)
- ✅ Identified AVB signing requirements for Unisoc SC9863A
- ✅ Verified Hovatek leaked key matches device's vbmeta signer
- ✅ Created signing toolchain (`scripts/13_sign_boot_avb.sh`)
- ✅ Generated signed `boot-droidian-signed.img` and matching `vbmeta-custom.img`

**Next:**
- Flash signed boot image and custom vbmeta for second boot test
- Debug kernel/initramfs if boot fails

**Key learnings:**
- This device has **NO hardware button combination** for fastboot mode
- `fastboot boot` (RAM boot) returns **protocol error** — not supported on this device
- Recovery requires **SPD Download Mode** (USB ID `1782:4d00`)
- The Linux `spd_dump` tool works for small partitions but struggles with the 3GB super partition
- vbmeta images must be exactly 1 MiB or flashing hangs indefinitely
- Full recovery may require **Windows SPD Flash Tool** with the original PAC firmware
- **Secure Boot remains active after bootloader unlock** — images must be AVB-signed

See [docs/UNISOC_AVB_SIGNING.md](docs/UNISOC_AVB_SIGNING.md) for the complete AVB signing guide.

See [docs/PHASE3_FIRST_BOOT.md](docs/PHASE3_FIRST_BOOT.md) for the first boot guide and recovery procedures.

See [droidian/PORTING_GUIDE.md](droidian/PORTING_GUIDE.md) for the full porting roadmap.

---

## Why Droidian Instead of postmarketOS?

While the **Unisoc SC9863A** has mainline kernel support (up to ~6.12), **postmarketOS is not viable** for this device due to the **GPU situation**:

| Component | Mainline Status |
|-----------|-----------------|
| SoC / CPU | Supported in mainline kernel |
| **GPU (PowerVR GE8322)** | **No Mesa driver exists** |
| Display | Potentially workable with mainline DRM |
| WiFi/BT/Modem | Would require significant work |

The **PowerVR GPU** is the blocker. Without Mesa support, there's no open-source graphics acceleration — the device would be limited to software rendering, making it effectively unusable for any graphical workload.

**Droidian** (or a Treble GSI) sidesteps this by using **libhybris** to run the Android HAL, giving us:
- Hardware-accelerated GPU via Android's proprietary PowerVR drivers
- Working display, touch, WiFi, Bluetooth, and modem
- A full Debian userspace (Phosh/GNOME) on top

This is the pragmatic path to a usable Linux tablet on PowerVR hardware.

---

## Purpose

The extraction pipeline acquires reliable, reproducible access to:

- the **kernel + initramfs/ramdisk** (`boot.img`)
- the **Device Tree** (`DTB (Device Tree Blob)` and `DTBO (Device Tree Blob Overlays)`)
- the **dynamic partition container** (`super.img`)
- the **vendor userspace payload** (modules/firmware + `VINTF (Vendor Interface)` metadata)
- the **AVB (Android Verified Boot)** verification metadata (`vbmeta*.img`)

This repository automates that baseline extraction so bringup work can focus on:
- Kernel compilation with Halium patches
- Device adaptation packaging
- Panel/touch/Wi-Fi/BT bringup
- Init + fstab translation for Droidian

---

## Input firmware (official)

Firmware is obtained from Teclast’s official download portal.

```text
Teclast firmware page:
https://www.teclast.com/en/firmware/shopifyfchk.php?c=n6h1
````

Example filename as published by Teclast:

* `P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar`

Only the **`.rar`** firmware archive is required.

---

## Repository layout

```text
.
├── LICENSE
├── README.md
├── scripts/                          # Extraction pipeline
│   ├── 00_devtools.sh
│   ├── 01_extract_firmware.sh
│   ├── 02_unpack_and_extract_dtb.sh
│   ├── 03_unpack_super_img.sh
│   ├── 04_extract_vendor_blobs.sh
│   ├── 05_collect_device_info.sh
│   ├── 06_extract_bootimg_info.sh
│   ├── 07_extract_vbmeta_info.sh
│   ├── 08_split_dtbo_overlays.sh
│   ├── 09_extract_ramdisk_init.sh
│   ├── 11_bringup_report.sh
│   ├── 12_unlock_bootloader.sh       # Manual only — not in run_all.sh
│   ├── 13_sign_boot_avb.sh           # Manual only — AVB signing for Unisoc
│   └── run_all.sh
├── docs/                             # Documentation
│   ├── PHASE3_FIRST_BOOT.md          # First boot testing guide
│   └── UNISOC_AVB_SIGNING.md         # ⚠️ Critical: AVB signing requirements
├── tools/                            # Helper tools
│   ├── hovatek_fastboot/             # Bootloader unlock tools (rsa4096_vbmeta.pem)
│   └── avb_signing/                  # AVB signing keys and outputs
├── kernel/                           # Kernel submodule
│   └── linux-teclast-p20hd/          # Samsung A03 Core kernel (p20hd branch)
└── droidian/                         # ← ACTIVE PORTING WORKSPACE
    ├── PORTING_GUIDE.md              # Step-by-step Droidian porting guide
    ├── kernel/
    │   ├── kernel-info.mk            # Boot parameters for Droidian kernel build
    │   └── fixup-mountpoints.patch   # Halium partition fixups for hybris-boot
    └── adaptation/
        ├── debian/                   # Debian packaging (control, rules, changelog)
        └── sparse/                   # Device-specific overlay files
```

During execution, the pipeline creates working output folders such as:

* `firmware/` — firmware archive staging + intermediate extracted content
* `backup/` — copies of boot-critical artifacts (boot/dtbo/vbmeta)
* `extracted/` — normalized extraction results (DTB, DTBO, super partitions, vendor payload)
* `device-info/` — runtime device signals collected through `ADB (Android Debug Bridge)`
* `reports/` — bringup report output (`bringup_report.md`)
* `logs/` — pipeline step logs (one log file per step)
* `tools/` — helper tooling cloned/built locally (pacextractor, AVB tooling, etc.)

---

## What gets extracted

From the official firmware package, the pipeline extracts and indexes:

* `boot.img` *(Linux kernel + initramfs/ramdisk)*
* `DTB (Device Tree Blob)` *(board hardware description)*
* `DTBO (Device Tree Blob Overlays)` *(hardware overlays and board variants)*
* `vbmeta*.img` *(AVB (Android Verified Boot) metadata)*
* `super.img` *(Android Dynamic Partitions container)*
* vendor bringup payload *(firmware/modules + `VINTF (Vendor Interface)` manifest/matrix)*

---

## Requirements

### Host System Setup (Distrobox)

This project is designed to run inside a **distrobox container** for maximum compatibility, especially on immutable Linux distributions (Fedora Silverblue/Kinoite, Bazzite, etc.).

**Create the distrobox (Ubuntu 22.04 recommended):**

```bash
distrobox create --name teclast-dev --image ubuntu:22.04
distrobox enter teclast-dev
```

All pipeline scripts should be run **inside the distrobox**:

```bash
# Option 1: Enter distrobox first
distrobox enter teclast-dev
bash scripts/run_all.sh

# Option 2: Run directly with distrobox
distrobox enter teclast-dev -- bash scripts/run_all.sh
```

### Android Device Preparation

For the best possible bringup report, the device should be prepared as follows:

#### 1. Enable Developer Options

On the Android device:
1. Go to **Settings** → **About tablet**
2. Tap **Build number** 7 times until "You are now a developer!" appears

#### 2. Enable USB Debugging

1. Go to **Settings** → **System** → **Developer options**
2. Enable **USB debugging**
3. Connect the device via USB cable
4. Accept the "Allow USB debugging?" prompt on the device (check "Always allow from this computer")

#### 3. Enable OEM Unlock (Recommended)

1. In **Developer options**, enable **OEM unlocking**
   - This allows bootloader unlock for future flashing
   - Note: The bootloader remains locked until you explicitly unlock it via fastboot

#### 4. Verify ADB Connection

```bash
# Inside distrobox
adb devices -l
```

You should see output like:
```
List of devices attached
0123456789ABCDEF       device usb:1-10.2 product:P20HD_EEA model:P20HD_EEA device:P20HD_EEA transport_id:1
```

If you see `unauthorized`, check the device screen for the USB debugging prompt.

#### 5. Optional: Collect Additional Runtime Data

For the most complete report, keep the device:
- **Powered on and unlocked** during `05_collect_device_info.sh`
- **Connected via USB** with ADB authorized

The script collects:
- Full `getprop` dump (device properties, bootloader status)
- Partition layout (`/dev/block/by-name/`)
- Input devices (touchscreen hints)
- Display info
- Loaded kernel modules
- SoC firmware info

### Software Requirements

The scripts target a Debian/Ubuntu-style environment and use `apt`.

**Primary runtime requirements:**

| Tool | Purpose |
|------|---------|
| `bash` | Script runtime |
| `git` | Clone helper repositories |
| `python3` | Script runtime + Python tools |
| `adb` | Android Debug Bridge — USB device communication |
| `fastboot` | Android Fastboot — bootloader flashing mode |
| `dtc` | Device Tree Compiler — DTB/DTS decompilation |
| `extract-dtb` | Python tool to extract DTBs from boot images |
| `simg2img` | Android sparse image converter |
| `lpunpack` | Android logical partition extractor |
| `unrar` / `7z` | RAR archive extraction |
| `debugfs` | ext4 filesystem extraction (fallback) |

**Step `scripts/00_devtools.sh` installs these automatically**, including:

* `device-tree-compiler` (provides `dtc`)
* `extract-dtb` Python package
* `AIK (Android Image Kitchen)` for boot image unpacking
* `pacextractor` for Spreadtrum/Unisoc `.pac` extraction
* fallback partition tools (if `lpunpack` is missing system-wide)
* `pmbootstrap` + `pmaports` (reference toolchain, useful for boot image tools)

### Manual Tool Installation (if needed)

Inside the distrobox:

```bash
# Core packages
sudo apt update
sudo apt install -y \
  device-tree-compiler \
  android-sdk-libsparse-utils \
  adb fastboot \
  e2fsprogs \
  unrar p7zip-full

# Python packages
pip3 install --user extract-dtb
```

---

## Quickstart (end-to-end)

### Step 1: Prepare the Environment

```bash
# Create and enter distrobox (first time only)
distrobox create --name teclast-dev --image ubuntu:22.04
distrobox enter teclast-dev

# Navigate to project directory
cd /path/to/teclast_p20hd_n6h1_postmarketos
```

### Step 2: Place the Firmware

Download the firmware from Teclast and place the `.rar` into the project root:

```bash
cp "~/Downloads/P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar" \
  ./P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar
```

### Step 3: Install Dependencies

```bash
# Inside distrobox
bash scripts/00_devtools.sh
```

### Step 4: Connect the Device (Optional but Recommended)

1. Enable Developer Options + USB Debugging on the device (see [Android Device Preparation](#android-device-preparation))
2. Connect via USB
3. Verify: `adb devices -l`

### Step 5: Run the Pipeline

```bash
# Inside distrobox if tools already installed (start from step 01)
bash scripts/run_all.sh --from 01
```

**Alternative invocation methods:**

```bash
# Explicit firmware selection
bash scripts/run_all.sh --firmware "./P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar"

# Non-interactive mode (auto-skip failures)
bash scripts/run_all.sh -y

# Start from a specific step
bash scripts/run_all.sh --from 03

# Run from outside distrobox
distrobox enter teclast-dev -- bash scripts/run_all.sh -y
```

### Step 6: Review the Report

```bash
# View the generated report
cat reports/bringup_report.md

# Or open in your favorite markdown viewer
```

---

## Idempotent behavior

The extraction pipeline is designed to be **safe to rerun**:

* output locations are stable (no random temporary directory sprawl)
* directories are created automatically
* existing artifacts are overwritten predictably where appropriate
* repeated execution refreshes extraction results in a consistent layout

This supports iteration-heavy bringup workflows (re-extract → validate → adjust → repeat).

---

## Script overview

### `scripts/run_all.sh`

Interactive pipeline runner for steps `00..10`:

* executes steps in order
* stores logs per step under `logs/`
* supports `--from <NN>` to start from a specific step
* supports non-interactive mode (`-y`) to skip failures automatically

---

### `scripts/00_devtools.sh`

Installs required packages and bootstraps tooling:

* `adb`, `fastboot`, `dtc`, sparse tools, compression tooling
* `AIK (Android Image Kitchen)` cloning and sanity patching
* `pacextractor` cloning and compilation
* attempts to provide `lpunpack/lpmake` if missing
* `pmbootstrap` + `pmaports` for postmarketOS bringup context

---

### `scripts/01_extract_firmware.sh`

Extracts official firmware:

* `.rar` *(Roshal archive)* → `.pac` *(Spreadtrum/Unisoc container)*
* `.pac` → extracted images (boot/dtbo/vbmeta/super/etc.)
* copies boot-critical images into `backup/` for safekeeping

---

### `scripts/02_unpack_and_extract_dtb.sh`

Unpacks the boot image and extracts DTB data:

* uses `AIK (Android Image Kitchen)` for boot image split
* uses `extract-dtb` to locate appended `DTB (Device Tree Blob)` data
* decompiles `.dtb → .dts` via `dtc`

---

### `scripts/03_unpack_super_img.sh`

Unpacks `super.img` (dynamic partitions):

* auto-detects `super.img` locations when possible
* converts sparse → raw with `simg2img` if necessary
* extracts logical partitions using `lpunpack` (binary or python fallback)

---

### `scripts/04_extract_vendor_blobs.sh`

Extracts vendor bringup payload from `vendor*.img`:

* attempts mount-based extraction (read-only loop mount)
* falls back to `debugfs` extraction when mounting is unavailable
* copies high-signal vendor content:

  * `lib/modules`
  * `firmware/`
  * `etc/vintf/manifest.xml`
  * `etc/vintf/compatibility_matrix.xml`
  * `build.prop`

---

### `scripts/05_collect_device_info.sh`

Collects runtime device information via `ADB (Android Debug Bridge)`:

* `getprop` full dump and subsets (boot/product/hardware)
* kernel identity (`uname -a`, `/proc/version`)
* attempts `/proc/cmdline` (often blocked on locked user builds)

Outputs are written under `device-info/`.

---

### `scripts/06_extract_bootimg_info.sh`

Extracts kernel bringup signals from the unpacked boot kernel:

* kernel file type detection
* Linux version string extraction (`strings`)
* `androidboot` string scanning
* optional scan for appended DTBs inside the kernel payload

Outputs are written under `extracted/kernel_info/`.

---

### `scripts/07_extract_vbmeta_info.sh`

Parses `vbmeta*.img` (AVB metadata):

* uses `avbtool` if present
* otherwise downloads `avbtool` from AOSP and runs it via python
* extracts partition verification info and flags into text reports

Outputs are written under `extracted/vbmeta_info/`.

---

### `scripts/08_split_dtbo_overlays.sh`

Splits `dtbo.img` into individual overlay DTBs:

* parses the DTBO table header and entries
* extracts each overlay blob as a `.dtb`
* decompiles `.dtb → .dts` with `dtc`

Outputs are written under `extracted/dtbo_split/`.

---

### `scripts/09_extract_ramdisk_init.sh`

Extracts high-signal init configuration from the boot ramdisk:

* `init*.rc`
* `fstab*`
* `ueventd*.rc`
* creates a small index report with grep hints

Outputs are written under `extracted/ramdisk_init/`.

---

### `scripts/11_bringup_report.sh`

Generates a consolidated Markdown bringup report:

* host environment + tooling sanity
* `getprop` identity (if available)
* boot command line signals
* DTB/DTBO high-signal pattern scans
* init/fstab/ueventd summaries
* super partition inventory
* vendor blob inventory
* vbmeta inventory + checksums

Output:

* `reports/bringup_report.md`

---

### `scripts/12_unlock_bootloader.sh`

Unlocks the bootloader on Unisoc SC9863A devices using the identifier token + signature method:

* Extracts and sets up Hovatek modified fastboot tools (user must download separately)
* Retrieves the device-specific identifier token via `fastboot oem get_identifier_token`
* Generates an RSA-4096 signature using the Hovatek signing key
* Sends the unlock command via `fastboot flashing unlock_bootloader signature.bin`

**This script is NOT run by `run_all.sh`** — it requires manual execution due to the destructive nature of bootloader unlocking (wipes all user data).

See [Bootloader Unlock](#bootloader-unlock-unisoc-sc9863a) for complete documentation.

---

### `scripts/13_sign_boot_avb.sh`

Signs boot images and creates custom vbmeta for Unisoc SC9863A devices:

* Auto-generates a custom boot signing keypair (RSA-4096) if not present
* Adds AVB hash footer to the boot image using `avbtool`
* Creates a custom vbmeta signed with the leaked Hovatek key
* Sets the boot chain partition to reference our custom public key
* Pads vbmeta to exactly 1 MiB (Unisoc requirement)

**This script is NOT run by `run_all.sh`** — it requires the boot image to be built first and is part of the flashing workflow.

**Output files:**
* `out/boot-droidian-signed.img` — AVB-signed boot image
* `out/vbmeta-custom.img` — Custom vbmeta (1 MiB, properly padded)

See [docs/UNISOC_AVB_SIGNING.md](docs/UNISOC_AVB_SIGNING.md) for complete AVB signing documentation.

---

## External Resources (Not Distributed)

Due to copyright and licensing restrictions, certain resources required for this project **cannot be distributed** in this repository. Users must download these manually from official sources.

### Required External Downloads

| Resource | Purpose | Download Location |
|----------|---------|-------------------|
| **Teclast Firmware (.rar)** | Official Android firmware for extraction | [Teclast Firmware Portal](https://www.teclast.com/en/firmware/shopifyfchk.php?c=n6h1) |
| **Hovatek Modified Fastboot** | Bootloader unlock tools for Unisoc devices | [Hovatek Forum Thread #32287](https://www.hovatek.com/forum/thread-32287.html) |

### Firmware Download

Download the official firmware from Teclast:

```text
https://www.teclast.com/en/firmware/shopifyfchk.php?c=n6h1
```

Example filename: `P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar`

Place the `.rar` file in the project root directory.

### Hovatek Modified Fastboot (for Bootloader Unlock)

The standard Android `fastboot` binary does not support Unisoc/Spreadtrum bootloader unlock commands. A modified fastboot is required.

**Download:** [Hovatek Forum - Modified Fastboot for Unisoc](https://www.hovatek.com/forum/thread-32287.html)

1. Download `[Hovatek] modified_fastboot.zip`
2. Place the zip file at: `tools/[Hovatek] modified_fastboot.zip`

The `12_unlock_bootloader.sh` script will extract and configure the tools automatically.

---

## Bootloader Unlock (Unisoc SC9863A)

Unlocking the bootloader is required to flash custom boot images (including postmarketOS). This section documents the complete bootloader unlock process for Unisoc SC9863A devices.

### Important Warnings

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  ⚠️  BOOTLOADER UNLOCK PERMANENTLY WIPES ALL USER DATA                       ║
║                                                                              ║
║  • All apps, settings, and personal data will be erased                      ║
║  • Internal storage will be formatted                                        ║
║  • This action cannot be undone — backup everything first!                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### How Unisoc Bootloader Unlock Works

Unlike Qualcomm or MediaTek devices, Unisoc (Spreadtrum) bootloaders use a **token + signature** unlock method:

1. **Get Identifier Token**: The bootloader provides a device-unique 32-byte hex token
2. **Sign the Token**: The token is signed with an RSA-4096 private key
3. **Send Signature**: The signature file is sent to unlock the bootloader

**Standard fastboot commands DO NOT work on Unisoc:**
- ❌ `fastboot flashing unlock` — Not supported
- ❌ `fastboot oem unlock` — Not supported
- ❌ `fastboot getvar all` — Returns nothing on Unisoc
- ❌ `fastboot getvar unlocked` — Not supported

**Unisoc-specific commands (require modified fastboot):**
- ✅ `fastboot oem get_identifier_token` — Returns the unlock token
- ✅ `fastboot flashing unlock_bootloader signature.bin` — Performs unlock

### Prerequisites

#### 1. Enable OEM Unlock on Device

On the Android device:
1. Go to **Settings** → **System** → **Developer options**
2. Enable **OEM unlocking**
   - If grayed out, ensure you have an internet connection and wait 7 days after first device setup (Google's anti-theft measure)

#### 2. Download Hovatek Modified Fastboot

1. Visit: [https://www.hovatek.com/forum/thread-32287.html](https://www.hovatek.com/forum/thread-32287.html)
2. Download `[Hovatek] modified_fastboot.zip`
3. Place in project: `tools/[Hovatek] modified_fastboot.zip`

#### 3. Ensure ADB/Fastboot Access

```bash
# Verify ADB connection
adb devices -l

# Reboot to fastboot mode
adb reboot bootloader

# OR: Power off, then hold Volume Down + Power until fastboot screen appears
```

### Unlock Procedure

#### Step 1: Check Current Bootloader Status (Safe)

```bash
bash scripts/12_unlock_bootloader.sh --check
```

This safely checks if the bootloader is already unlocked without making any changes.

#### Step 2: Perform Bootloader Unlock

```bash
bash scripts/12_unlock_bootloader.sh
```

The script will:
1. Extract Hovatek tools from the downloaded zip
2. Delete any pre-existing signature.bin (must be regenerated per-device)
3. Request the identifier token from the bootloader
4. Generate a device-specific signature using RSA-4096 signing
5. Send the unlock command
6. Prompt you to confirm on the device (Volume Down to confirm)

#### Step 3: Confirm on Device

When prompted on the tablet screen:
- Press **Volume Down** to confirm unlock
- The device will erase all user data and reboot
- This takes about 10-15 minutes wait patiently until reboot to Android setup.

### Script Options

```bash
# Check bootloader status only (no changes)
bash scripts/12_unlock_bootloader.sh --check

# Perform full unlock process
bash scripts/12_unlock_bootloader.sh

# Skip status check and go directly to unlock
bash scripts/12_unlock_bootloader.sh --skip-check

# Show help
bash scripts/12_unlock_bootloader.sh --help
```

### Verification

After unlock completes, the device will:
1. Display "LOCK FLAG IS: UNLOCK" warning at boot
2. Wipe all user data and reboot to initial setup

Verify unlock status:
```bash
adb reboot bootloader
bash scripts/12_unlock_bootloader.sh --check
```

### Troubleshooting Bootloader Unlock

#### "Modified fastboot zip not found"

**Fix:** Download from Hovatek and place at `tools/[Hovatek] modified_fastboot.zip`

#### "Device not in fastboot mode"

**Fix:**
```bash
adb reboot bootloader
# OR: Power off → Hold Volume Down + Power
```

#### "FAILED (remote: unknown command)"

**Cause:** Using standard fastboot instead of Hovatek modified version.

**Fix:** Ensure the script is using `tools/hovatek_fastboot/fastboot` not system fastboot.

#### Identifier token not captured

**Cause:** Device not responding or wrong mode.

**Fix:**
1. Ensure device shows "FASTBOOT MODE" on screen
2. Try unplugging and replugging USB cable
3. Use `lsusb` to verify device is detected

#### Signature verification failed

**Cause:** Token/signature mismatch or corrupted signature.

**Fix:** The script regenerates signature.bin each run. If issues persist, manually delete `tools/hovatek_fastboot/signature.bin` and retry.

### Post-Unlock: Next Steps

After successfully unlocking the bootloader:

1. ~~**Test boot image in RAM (safe, non-persistent):**~~ **NOT SUPPORTED**
   ```bash
   # This does NOT work on P20HD - returns protocol error
   fastboot boot boot-pmos.img
   ```
   > ⚠️ The Unisoc bootloader on this device does not support RAM boot. You must flash directly.

2. **Flash boot image** (requires SPD recovery tools ready):
   ```bash
   # ⚠️ CAUTION: This modifies the device permanently
   # Have SPD Flash Tool ready before attempting!
   fastboot flash boot boot-droidian.img
   ```

3. **To re-lock bootloader** (restores stock security):
   ```bash
   fastboot flashing lock
   ```
   ⚠️ Only re-lock with stock firmware! Re-locking with custom firmware WILL MOST LIKELY brick the device.

   DO NOT FLASH OR LOCK UNLESS 100% SURE OF WHAT YOU ARE DOING. ALWAYS HAVE SPD RECOVERY READY.

---

## Notes / caveats

* Locked production devices may restrict access to certain runtime nodes (e.g. `/proc/cmdline`).
* This workspace is designed for **repeatable bringup extraction**, not final flashing workflows.
* The Droidian port is a work-in-progress — see [droidian/PORTING_GUIDE.md](droidian/PORTING_GUIDE.md) for current status.

---

## Troubleshooting

### Common Issues

#### "command not found: dtc" or "ModuleNotFoundError: extract_dtb"

**Cause:** Running scripts outside the distrobox, or tools not installed.

**Fix:**
```bash
# Make sure you're inside distrobox
distrobox enter teclast-dev

# Verify tools are installed
which dtc
python3 -c "import extract_dtb; print('OK')"

# If missing, install manually
sudo apt install -y device-tree-compiler
pip3 install --user extract-dtb
```

#### ADB shows "no devices" or "unauthorized"

**Cause:** USB debugging not enabled, or device not authorized.

**Fix:**
1. Check device screen for "Allow USB debugging?" prompt
2. Ensure USB cable supports data transfer (not charge-only)
3. Try different USB port
4. Restart ADB server: `adb kill-server && adb devices`

#### "lpunpack: command not found"

**Cause:** `lpunpack` not installed or not in PATH.

**Fix:** The pipeline uses a Python fallback automatically. If issues persist:
```bash
# Check if lpunpack exists
which lpunpack

# Use Python fallback explicitly
python3 tools/lpunpack.py extracted/super.raw.img extracted/super_lpunpack/
```

#### Vendor kernel modules empty (0 .ko files)

**Cause:** `debugfs` extraction has limitations with some directory structures.

**Fix:** Mount vendor.img manually with root privileges:
```bash
sudo mount -o loop,ro extracted/super_lpunpack/vendor.img /mnt
cp -a /mnt/lib/modules extracted/vendor_blobs/lib/
sudo umount /mnt
```

#### Sparse image errors

**Cause:** Image needs conversion from Android sparse format to raw.

**Fix:**
```bash
simg2img input.img output.raw.img
```

#### Script fails with "set -e" errors

**Cause:** Bash strict mode exits on any command failure.

**Fix:** Most scripts handle this gracefully. If a specific command fails:
- Check the log file in `logs/` for details
- Use `--from NN` to resume from a specific step

### Report Quality Checklist

For the **best possible bringup report**, ensure:

| Item | Status | How to Check |
|------|--------|--------------|
| Device connected via ADB | Required for runtime data | `adb devices -l` shows device |
| USB debugging authorized | Required | No "unauthorized" in adb devices |
| Developer options enabled | Required for ADB | Device settings |
| OEM unlock enabled | Recommended | Developer options → OEM unlocking |
| Device screen unlocked | Recommended | Prevents ADB timeouts |
| Firmware .rar present | Required | File exists in project root |
| Distrobox entered | Required | Run inside `teclast-dev` |
| 00_devtools.sh completed | Required | Tools installed successfully |

### What Each Script Needs

| Script | Needs Device? | Needs Firmware? | Notes |
|--------|--------------|-----------------|-------|
| 00_devtools.sh | No | No | Installs tools only |
| 01_extract_firmware.sh | No | Yes | Extracts .rar → .pac → images |
| 02_unpack_and_extract_dtb.sh | No | Yes (boot.img) | Needs `dtc`, `extract-dtb` |
| 03_unpack_super_img.sh | No | Yes (super.img) | Needs `lpunpack`, `simg2img` |
| 04_extract_vendor_blobs.sh | No | Yes (vendor.img) | May need `sudo` for best results |
| 05_collect_device_info.sh | **Yes** | No | Collects runtime device data |
| 06_extract_bootimg_info.sh | No | Yes (boot.img) | Analyzes kernel binary |
| 07_extract_vbmeta_info.sh | No | Yes (vbmeta*.img) | Parses AVB metadata |
| 08_split_dtbo_overlays.sh | No | Yes (dtbo.img) | Needs `dtc` |
| 09_extract_ramdisk_init.sh | No | Yes (ramdisk) | Extracts init configs |
| 11_bringup_report.sh | Optional | Yes | Generates final report |
| 12_unlock_bootloader.sh | **Yes** (fastboot) | No | Needs Hovatek tools (see [External Resources](#external-resources-not-distributed)) |

---

## Output overview (typical)

After a successful run, the extraction layout typically includes:

* `backup/boot-stock.img`
* `backup/dtbo.img`
* `backup/vbmeta*.img`
* `extracted/dtb_from_bootimg/*.dtb` and `*.dts`
* `extracted/dtbo_split/*.dtb` and `*.dts`
* `extracted/super_lpunpack/*.img`
* `extracted/vendor_blobs/...`
* `extracted/ramdisk_init/...`
* `device-info/...`
* `reports/bringup_report.md`
* `logs/*.log`
* `tools/hovatek_fastboot/` — Extracted Hovatek tools (after running `12_unlock_bootloader.sh`)
* `droidian/` — Droidian porting files (kernel-info.mk, adaptation package skeleton)

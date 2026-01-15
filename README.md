# Teclast P20HD (N6H1 / Unisoc SC9863A) — postmarketOS Bringup Extraction Workspace

This repository contains a **bringup extraction and indexing pipeline** for starting a **postmarketOS** device port for the **Teclast P20HD EEA** tablet (**N6H1**, **Unisoc SC9863A / s9863a1h10**).

The focus is **artifact extraction**, **structured output layout**, and **high-signal bringup reporting** from **official Android firmware**.

It is not a complete postmarketOS port (yet).

---

## Purpose

A postmarketOS port typically begins with acquiring reliable, reproducible access to:

- the **kernel + initramfs/ramdisk** (`boot.img`)
- the **Device Tree** (`DTB (Device Tree Blob)` and `DTBO (Device Tree Blob Overlays)`)
- the **dynamic partition container** (`super.img`)
- the **vendor userspace payload** (modules/firmware + `VINTF (Vendor Interface)` metadata)
- the **AVB (Android Verified Boot)` verification metadata (`vbmeta*.img`)

This repository automates that baseline extraction so bringup work can focus on:
- `deviceinfo` authoring
- panel/touch/Wi-Fi/BT bringup
- kernel/DT alignment
- init + fstab translation and debugging

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
└── scripts
    ├── 00_devtools.sh
    ├── 01_extract_firmware.sh
    ├── 02_unpack_and_extract_dtb.sh
    ├── 03_unpack_super_img.sh
    ├── 04_extract_vendor_blobs.sh
    ├── 05_collect_device_info.sh
    ├── 06_extract_kernel_info.sh
    ├── 07_extract_vbmeta_info.sh
    ├── 08_split_dtbo_overlays.sh
    ├── 09_extract_ramdisk_init.sh
    ├── 10_bringup_report.sh
    └── run_all.sh
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
* `pmbootstrap` + `pmaports` (postmarketOS reference toolchain/tree)
* fallback partition tools (if `lpunpack` is missing system-wide)

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

### `scripts/06_extract_kernel_info.sh`

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

### `scripts/10_bringup_report.sh`

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

## Notes / caveats

* Locked production devices may restrict access to certain runtime nodes (e.g. `/proc/cmdline`).
* This workspace is designed for **repeatable bringup extraction**, not final flashing workflows.

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
| 06_extract_kernel_info.sh | No | Yes (boot.img) | Analyzes kernel binary |
| 07_extract_vbmeta_info.sh | No | Yes (vbmeta*.img) | Parses AVB metadata |
| 08_split_dtbo_overlays.sh | No | Yes (dtbo.img) | Needs `dtc` |
| 09_extract_ramdisk_init.sh | No | Yes (ramdisk) | Extracts init configs |
| 10_bringup_report.sh | Optional | Yes | Generates final report |

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

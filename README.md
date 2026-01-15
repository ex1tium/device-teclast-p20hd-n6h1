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

The scripts target a Debian/Ubuntu-style host and use `apt`.

Primary runtime requirements:

* `bash`
* `git`
* `python3`
* `adb` *(Android Debug Bridge — USB device communication)*
* `fastboot` *(Android Fastboot — bootloader flashing mode)*
* `dtc` *(Device Tree Compiler — DTB/DTS toolchain)*
* `simg2img` *(Android sparse image converter)*
* `lpunpack` *(Android logical partition extractor)*

Step `scripts/00_devtools.sh` installs these automatically and also sets up:

* `AIK (Android Image Kitchen)` for boot image unpacking
* `pacextractor` for Spreadtrum/Unisoc `.pac` extraction
* `pmbootstrap` + `pmaports` (postmarketOS reference toolchain/tree)
* fallback partition tools (if `lpunpack` is missing system-wide)

---

## Quickstart (end-to-end)

Place the firmware `.rar` into the project root (recommended):

```bash
cp "~/Downloads/P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar" \
  ./P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar
```

Install toolchain + workspace dependencies:

```bash
bash scripts/00_devtools.sh
```

Run the full extraction pipeline:

```bash
bash scripts/run_all.sh
```

The pipeline runner supports explicit firmware selection:

```bash
bash scripts/run_all.sh --firmware "./P20HD(N6H1)_Android10.0_EEA_V1.07_20211023.rar"
```

Non-interactive mode is supported:

```bash
bash scripts/run_all.sh -y
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

## Troubleshooting signals

Common issues encountered during early bringup extraction:

* `lpunpack` missing: ensure Step `00_devtools.sh` was executed successfully
* sparse images: `simg2img` conversion is required before mounting/inspection
* container/mount limitations: vendor extraction falls back to `debugfs`
* unusual firmware layouts: Unisoc packages may nest images under `.pac` contents

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

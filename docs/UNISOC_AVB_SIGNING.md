# Unisoc AVB Signing Guide for SC9863A

This document explains Android Verified Boot (AVB) signing requirements for Unisoc SC9863A devices like the Teclast P20HD, and how to create properly signed boot images.

## Critical Finding: Secure Boot Remains Active After Unlock

**Even with an unlocked bootloader, Unisoc devices still enforce Secure Boot signature verification.**

This means:
- Simply unlocking the bootloader is NOT enough to flash custom images
- Boot, recovery, and vbmeta partitions must be **cryptographically signed**
- The bootloader verifies signatures against public keys stored in vbmeta
- Unsigned or incorrectly signed images cause bootloops or boot failures

## How AVB Works on Unisoc Devices

### Chain of Trust

```
┌─────────────────────────────────────────────────────────────┐
│                      vbmeta partition                        │
│  - Signed with OEM's vbmeta key                             │
│  - Contains chain partition descriptors pointing to         │
│    public keys for: boot, dtbo, recovery, system, etc.      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      boot partition                          │
│  - Contains hash footer signed with boot signing key        │
│  - Public key must match what vbmeta expects                │
└─────────────────────────────────────────────────────────────┘
```

### P20HD Stock vbmeta Analysis

```
Algorithm:                SHA256_RSA4096
Public key (sha1):        2597c218aae470a130f61162feaae70afd97f011  ← vbmeta signer

Chain Partition Descriptors:
  boot      → ea410c1b46cdb2e40e526880ff383f083bd615d5
  dtbo      → ea410c1b46cdb2e40e526880ff383f083bd615d5
  recovery  → d9093b9a181bdb5731b44d60a9f850dc724e2874
  vbmeta_system → e2c66ff8a1d787d7bf898711187bff150f691d27
  vbmeta_vendor → 9885bf5bf909e5208dfd42abaf51ad9b104ee117
  ...
```

### Key Discovery

**Good news:** Many Unisoc OEMs use the same leaked signing key (`rsa4096_vbmeta.pem`).

| Key | SHA1 Hash | Status |
|-----|-----------|--------|
| Leaked vbmeta key | `2597c218aae470a130f61162feaae70afd97f011` | ✅ Matches P20HD |
| Stock boot key | `ea410c1b46cdb2e40e526880ff383f083bd615d5` | ❌ Private key unknown |

The leaked `rsa4096_vbmeta.pem` matches the P20HD's vbmeta signing key, which means we can create custom vbmeta images that the bootloader will accept.

## Solution: Custom Signed vbmeta + Boot

Since we have the vbmeta signing key but NOT the boot signing key, the solution is:

1. **Generate our own boot signing keypair**
2. **Create a custom vbmeta** that:
   - Is signed with the leaked vbmeta key (which the bootloader trusts)
   - Points the boot chain partition to OUR public key
3. **Sign our boot image** with our private key
4. **Flash both** vbmeta and boot together

### Signing Workflow

```bash
# Run the signing script (auto-generates boot signing key if missing)
./scripts/13_sign_boot_avb.sh

# Output:
#   out/boot-droidian-signed.img  - AVB-signed boot image
#   out/vbmeta-custom.img         - Custom vbmeta (1 MiB, padded)
```

The script automatically generates `tools/avb_signing/boot_signing.pem` (RSA-4096) on first run if it doesn't exist.

## Signing Script Details

The script `scripts/13_sign_boot_avb.sh` performs:

1. **Extract public key** from our boot signing key
2. **Add AVB hash footer** to boot image using our key
3. **Create custom vbmeta** with:
   - Signed by leaked `rsa4096_vbmeta.pem`
   - Boot chain partition → our public key
   - Flag 2 (verification disabled for other partitions)
4. **Pad vbmeta** to exactly 1 MiB (Unisoc requirement)

### Output Verification

```
vbmeta-custom.img:
  Public key (sha1): 2597c218aae470a130f61162feaae70afd97f011  ← Leaked key ✓
  Flags: 2  ← Verification disabled for non-chained partitions
  Chain: boot:1:6e41e49eea379071ad4afced336e2c4b62783843  ← Our key

boot-droidian-signed.img:
  Public key (sha1): 6e41e49eea379071ad4afced336e2c4b62783843  ← Matches chain ✓
  Algorithm: SHA256_RSA4096
  Partition size: 36700160 bytes
```

## Flashing Procedure

```bash
# Enter fastboot (from working Android only)
adb reboot bootloader

# Flash custom vbmeta FIRST
fastboot flash vbmeta out/vbmeta-custom.img

# Flash signed boot image
fastboot flash boot out/boot-droidian-signed.img

# Reboot
fastboot reboot
```

> **WARNING:** Have SPD recovery tools ready before flashing. See [PHASE3_FIRST_BOOT.md](PHASE3_FIRST_BOOT.md) for recovery procedures.

## Unisoc-Specific Requirements

### vbmeta Size Must Be Exactly 1 MiB

The Unisoc bootloader rejects vbmeta images that aren't exactly 1,048,576 bytes. The signing script automatically pads the image.

### No RAM Boot Support

The P20HD bootloader does not support `fastboot boot` (RAM boot). You must flash directly to test, which makes recovery preparation essential.

### Secure Boot vs Bootloader Lock

| State | Can Flash | Verification |
|-------|-----------|--------------|
| Locked bootloader | ❌ No | Full AVB |
| Unlocked bootloader | ✅ Yes | **Still enforced** |
| Unlocked + custom vbmeta | ✅ Yes | Only for chained partitions |

## Key Files

| File | Purpose | Source |
|------|---------|--------|
| `tools/hovatek_fastboot/rsa4096_vbmeta.pem` | Leaked Unisoc vbmeta signing key | [Hovatek download](https://www.hovatek.com/forum/thread-32287.html) |
| `tools/avb_signing/boot_signing.pem` | Custom boot signing key | Auto-generated by script |
| `tools/avb_signing/keys/boot_pubkey.bin` | Public key for vbmeta chain | Auto-generated by script |
| `scripts/13_sign_boot_avb.sh` | Automated signing script | This repo |

## References

- [Hovatek: Custom signed vbmeta for Unisoc](https://www.hovatek.com/forum/thread-32664.html)
- [Hovatek: Sign Unisoc images with AVBtool](https://www.hovatek.com/forum/thread-32674.html)
- [GitHub: treble_experimentations #2614](https://github.com/phhusson/treble_experimentations/issues/2614)
- [GitHub: treble_experimentations #1602](https://github.com/phhusson/treble_experimentations/issues/1602)
- [Android AVB Documentation](https://android.googlesource.com/platform/external/avb/+/master/README.md)

## Troubleshooting

### Bootloop after flashing

- Verify vbmeta was flashed BEFORE boot
- Check vbmeta is exactly 1 MiB: `stat -c%s out/vbmeta-custom.img`
- Verify public key chain matches: boot image key SHA1 must match vbmeta chain descriptor

### "writing vbmeta" hangs in fastboot

- vbmeta is not exactly 1 MiB
- Use the signing script which handles padding automatically

### Device stuck at splash screen

- Boot image signature doesn't match vbmeta chain
- Recover using SPD Download Mode (see PHASE3_FIRST_BOOT.md)

## Alternative Approaches Considered

### DSU Sideloader
- **Status:** Not viable
- **Reason:** SELinux denials block DSU on SC9863A; requires root to work around

### GSI Direct Flash
- **Status:** Potentially viable
- **Note:** AOSP 10 GSIs reportedly boot on SC9863A without vbmeta changes when flashing to super partition only
- **Limitation:** Doesn't help with custom kernel testing

### avbtool --disable-verification flags
- **Status:** Insufficient alone
- **Reason:** Unisoc bootloader still checks vbmeta signature even with verification flags

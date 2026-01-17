#!/bin/bash
#
# 13_sign_boot_avb.sh - Sign boot image and create custom vbmeta for Unisoc SC9863A
#
# This script creates AVB-signed boot image and matching vbmeta for the P20HD.
# Based on Hovatek guides for Unisoc devices.
#
# Prerequisites:
#   - avbtool (from AOSP platform-tools or pip install avbtool)
#   - tools/hovatek_fastboot/rsa4096_vbmeta.pem (leaked Unisoc vbmeta key, from Hovatek download)
#
# The boot signing key (tools/avb_signing/boot_signing.pem) is auto-generated if missing.
#
# References:
#   - https://www.hovatek.com/forum/thread-32664.html (custom vbmeta)
#   - https://www.hovatek.com/forum/thread-32674.html (signing images)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Paths
VBMETA_KEY="tools/hovatek_fastboot/rsa4096_vbmeta.pem"
BOOT_KEY="tools/avb_signing/boot_signing.pem"
KEYS_DIR="tools/avb_signing/keys"
INPUT_BOOT="out/boot-droidian.img"
OUTPUT_BOOT="out/boot-droidian-signed.img"
OUTPUT_VBMETA="out/vbmeta-custom.img"

# Boot partition parameters (from stock boot.img)
BOOT_PARTITION_SIZE=36700160  # 35 MB
ALGORITHM="SHA256_RSA4096"

echo "=== Unisoc AVB Boot Signing Script ==="
echo ""

# Check prerequisites
if ! command -v avbtool &> /dev/null; then
    echo "ERROR: avbtool not found. Install with: pip install avbtool"
    exit 1
fi

if [[ ! -f "$VBMETA_KEY" ]]; then
    echo "ERROR: vbmeta signing key not found: $VBMETA_KEY"
    exit 1
fi

# Auto-generate boot signing key if missing
if [[ ! -f "$BOOT_KEY" ]]; then
    echo "Boot signing key not found. Generating new RSA-4096 key..."
    mkdir -p "$(dirname "$BOOT_KEY")"
    openssl genrsa -out "$BOOT_KEY" 4096 2>/dev/null
    echo "Generated: $BOOT_KEY"
fi

if [[ ! -f "$INPUT_BOOT" ]]; then
    echo "ERROR: Input boot image not found: $INPUT_BOOT"
    exit 1
fi

mkdir -p "$KEYS_DIR"
mkdir -p out

# Step 1: Extract public key from boot signing key
echo "[1/4] Extracting public key from boot signing key..."
avbtool extract_public_key --key "$BOOT_KEY" --output "$KEYS_DIR/boot_pubkey.bin"
BOOT_PUBKEY_SHA1=$(sha1sum "$KEYS_DIR/boot_pubkey.bin" | cut -d' ' -f1)
echo "      Boot public key SHA1: $BOOT_PUBKEY_SHA1"

# Step 2: Copy and sign boot image
echo "[2/4] Signing boot image..."
cp "$INPUT_BOOT" "$OUTPUT_BOOT"

# Get current image size
CURRENT_SIZE=$(stat -c%s "$OUTPUT_BOOT")
echo "      Input image size: $CURRENT_SIZE bytes"

# Check if image already has AVB footer (and remove it if so)
if avbtool info_image --image "$OUTPUT_BOOT" &>/dev/null; then
    echo "      Removing existing AVB footer..."
    avbtool erase_footer --image "$OUTPUT_BOOT"
fi

# Add hash footer with our signing key
avbtool add_hash_footer \
    --image "$OUTPUT_BOOT" \
    --partition_name boot \
    --partition_size "$BOOT_PARTITION_SIZE" \
    --key "$BOOT_KEY" \
    --algorithm "$ALGORITHM" \
    --prop com.android.build.boot.os_version:10

SIGNED_SIZE=$(stat -c%s "$OUTPUT_BOOT")
echo "      Signed image size: $SIGNED_SIZE bytes"

# Verify the signed image
echo "      Verifying signed boot image..."
avbtool info_image --image "$OUTPUT_BOOT" | head -20

# Step 3: Create custom vbmeta
echo ""
echo "[3/4] Creating custom vbmeta image..."

# Create vbmeta with:
# - Signed with the leaked Unisoc key (rsa4096_vbmeta.pem)
# - Boot chain partition pointing to our custom public key
# - Flag 2 = AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED for other partitions
#
# Note: We only chain the boot partition since that's what we're replacing.
# Other partitions keep their stock signatures.

avbtool make_vbmeta_image \
    --key "$VBMETA_KEY" \
    --algorithm "$ALGORITHM" \
    --flag 2 \
    --chain_partition boot:1:"$KEYS_DIR/boot_pubkey.bin" \
    --padding_size 20480 \
    --output "$OUTPUT_VBMETA"

echo "      Created vbmeta (before padding): $(stat -c%s "$OUTPUT_VBMETA") bytes"

# Step 4: Pad vbmeta to exactly 1 MiB (Unisoc requirement)
echo ""
echo "[4/4] Padding vbmeta to 1 MiB..."

TARGET_SIZE=1048576  # 1 MiB
CURRENT_VBMETA_SIZE=$(stat -c%s "$OUTPUT_VBMETA")

if [[ $CURRENT_VBMETA_SIZE -lt $TARGET_SIZE ]]; then
    # Pad with zeros
    dd if=/dev/zero bs=1 count=$((TARGET_SIZE - CURRENT_VBMETA_SIZE)) >> "$OUTPUT_VBMETA" 2>/dev/null
    echo "      Padded from $CURRENT_VBMETA_SIZE to $(stat -c%s "$OUTPUT_VBMETA") bytes"
elif [[ $CURRENT_VBMETA_SIZE -gt $TARGET_SIZE ]]; then
    echo "ERROR: vbmeta image is larger than 1 MiB!"
    exit 1
fi

# Final verification
echo ""
echo "=== Output Files ==="
ls -la "$OUTPUT_BOOT" "$OUTPUT_VBMETA"

echo ""
echo "=== vbmeta Info ==="
avbtool info_image --image "$OUTPUT_VBMETA"

echo ""
echo "=== Done ==="
echo ""
echo "To flash (DANGEROUS - have SPD recovery ready!):"
echo "  1. adb reboot bootloader"
echo "  2. fastboot flash vbmeta $OUTPUT_VBMETA"
echo "  3. fastboot flash boot $OUTPUT_BOOT"
echo "  4. fastboot reboot"

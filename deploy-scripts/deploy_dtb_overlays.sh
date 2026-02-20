#!/bin/bash

# deploy_dtb_overlays.sh
#
# Deploys the pre-merged uConsole DTB to the device.
#
# The file rk3588s-radxa-cm5-uconsole-merged.dtb is built directly from
# the kernel source tree and already contains the CWU50 panel node, AXP20x
# PMIC nodes, and DSI1 configuration — no fdtoverlay step needed.
#
# Run this from the kernel source root after:
#   make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image modules dtbs
#
# After running this script, ensure extlinux.conf has:
#   fdt /boot/dtbs/uconsole-cm5/rk3588s-radxa-cm5-uconsole-merged.dtb
#
# Usage: ./deploy-scripts/deploy_dtb_overlays.sh

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REMOTE_USER="clockwork"
REMOTE_HOST="192.168.1.174"

# ---------------------------------------------------------------------------
# Local source path (relative to kernel source root)
#
# This DTB is built from source and has the display + PMIC nodes already
# merged in — it is the correct DTB for the uConsole CM5 hardware.
# ---------------------------------------------------------------------------
MERGED_DTB="arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-merged.dtb"

# ---------------------------------------------------------------------------
# Remote install path — matches what extlinux.conf should reference
# ---------------------------------------------------------------------------
REMOTE_DTB_PATH="/boot/dtbs/uconsole-cm5/rk3588s-radxa-cm5-uconsole-merged.dtb"

# ---------------------------------------------------------------------------
# Sanity check — abort early if the DTB wasn't built yet
# ---------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "DTB Deploy  ->  $REMOTE_USER@$REMOTE_HOST"
echo "--------------------------------------------------------"

if [[ ! -f "$MERGED_DTB" ]]; then
    echo "ERROR: missing file: $MERGED_DTB"
    echo "Have you run 'make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs' yet?"
    exit 1
fi

# ---------------------------------------------------------------------------
# Read password once, reuse for all sshpass calls
# ---------------------------------------------------------------------------
read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " SSHPASS
export SSHPASS
echo ""

# ---------------------------------------------------------------------------
# Copy DTB to the device and install it to /boot (requires sudo)
# ---------------------------------------------------------------------------
echo "[1/2] Copying DTB to device..."
sshpass -e rsync -avq \
    "$MERGED_DTB" "$REMOTE_USER@$REMOTE_HOST:~/rk3588s-radxa-cm5-uconsole-merged.dtb"

echo "[2/2] Installing DTB to /boot (requires remote sudo)..."
sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
set -e
echo '$SSHPASS' | sudo -S -p '' mkdir -p /boot/dtbs/uconsole-cm5
echo '$SSHPASS' | sudo -S -p '' cp ~/rk3588s-radxa-cm5-uconsole-merged.dtb $REMOTE_DTB_PATH
rm ~/rk3588s-radxa-cm5-uconsole-merged.dtb
echo '-> DTB installed to $REMOTE_DTB_PATH'
"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo "--------------------------------------------------------"
echo "DTB installed to: $REMOTE_DTB_PATH"
echo ""
echo "Make sure extlinux.conf has:"
echo "  fdt $REMOTE_DTB_PATH"
echo "  (no fdtoverlays line — panel/PMIC nodes are already in the DTB)"
echo "--------------------------------------------------------"

unset SSHPASS

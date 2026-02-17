#!/bin/bash

# Configuration
REMOTE_USER="archuser"
REMOTE_HOST="192.168.1.174"
STAGING_DIR="~/kernel-deploy-tmp"

# Local Paths
KERNEL_IMAGE="arch/arm64/boot/Image"
DTB_FILES="arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5*.dtb"
MODULES_DIR="/home/doraemon/cm5-kernel-staging/lib/modules/"

# Target Remote Paths
TARGET_KERNEL="/boot/vmlinuz-linux-uconsole"
TARGET_DTB_DIR="/boot/dtbs/uconsole-cm5/"
TARGET_MODULES_DIR="/lib/modules/"

echo "--------------------------------------------------------"
echo "Deploying kernel to $REMOTE_USER@$REMOTE_HOST"
echo "Target Kernel:  $TARGET_KERNEL"
echo "Target DTBs:    $TARGET_DTB_DIR"
echo "Target Modules: $TARGET_MODULES_DIR"
echo "--------------------------------------------------------"

# Read password safely
read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " SSHPASS
export SSHPASS
echo ""

# 1. Create Staging Directory
echo "[1/4] Preparing remote staging area..."
sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $STAGING_DIR/dtbs $STAGING_DIR/modules"

# 2. Transfer Files to Staging
echo "[2/4] Transferring files..."
# Kernel
sshpass -e rsync -avq "$KERNEL_IMAGE" "$REMOTE_USER@$REMOTE_HOST:$STAGING_DIR/Image"
# DTBs
sshpass -e rsync -avq $DTB_FILES "$REMOTE_USER@$REMOTE_HOST:$STAGING_DIR/dtbs/"
# Modules
sshpass -e rsync -avq "$MODULES_DIR" "$REMOTE_USER@$REMOTE_HOST:$STAGING_DIR/modules/"

# 3. Move Files to Final Destination (using sudo)
echo "[3/4] Installing to system directories (requires remote sudo)..."

REMOTE_COMMANDS="
echo '$SSHPASS' | sudo -S -p '' true && \
echo '-> Installing Kernel Image...' && \
sudo cp $STAGING_DIR/Image $TARGET_KERNEL && \
echo '-> Installing Device Trees...' && \
sudo mkdir -p $TARGET_DTB_DIR && \
sudo cp $STAGING_DIR/dtbs/* $TARGET_DTB_DIR && \
echo '-> Installing Modules...' && \
sudo cp -r $STAGING_DIR/modules/* $TARGET_MODULES_DIR && \
echo '-> Cleaning up staging...' && \
rm -rf $STAGING_DIR
"

sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_COMMANDS"

echo "--------------------------------------------------------"
echo "Deployment Complete!"
echo "Please reboot your device to apply changes."
echo "--------------------------------------------------------"

unset SSHPASS

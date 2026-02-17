#!/bin/bash

# Configuration
REMOTE_USER="archuser"
REMOTE_HOST="192.168.1.174"
FIXED_DTB="arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-fixed.dtb"
REMOTE_DTB_DIR="/boot/dtbs/uconsole-cm5"
TARGET_DTB_NAME="rk3588s-radxa-cm5-uconsole-fixed.dtb"

echo "--------------------------------------------------------"
echo "Deploying Fixed Device Tree to $REMOTE_USER@$REMOTE_HOST"
echo "--------------------------------------------------------"

# Read password safely
read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " SSHPASS
export SSHPASS
echo ""

# 1. Transfer DTB
echo "[1/3] Transferring fixed DTB..."
sshpass -e scp -o StrictHostKeyChecking=no "$FIXED_DTB" "$REMOTE_USER@$REMOTE_HOST:~/$TARGET_DTB_NAME"

# 2. Install DTB and Update Config
echo "[2/3] Installing and updating boot config..."
REMOTE_COMMANDS="
echo '$SSHPASS' | sudo -S -p '' true && 
echo '-> Backing up extlinux.conf...' && 
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak && 
echo '-> Installing DTB...' && 
sudo mv ~/$TARGET_DTB_NAME $REMOTE_DTB_DIR/$TARGET_DTB_NAME && 
echo '-> Updating extlinux.conf...' && 
sudo sed -i 's/rk3588s-radxa-cm5-uconsole-merged.dtb/$TARGET_DTB_NAME/' /boot/extlinux/extlinux.conf
"

sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_COMMANDS"

echo "--------------------------------------------------------"
echo "Fix Deployed!"
echo "Please reboot your device manually: ssh $REMOTE_USER@$REMOTE_HOST 'sudo reboot'"
echo "--------------------------------------------------------"

unset SSHPASS

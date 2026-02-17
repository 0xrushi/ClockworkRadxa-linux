#!/bin/bash

# Configuration
REMOTE_USER="archuser"
REMOTE_HOST="192.168.1.174"
NEW_KERNEL="/boot/vmlinuz-linux-uconsole"

echo "--------------------------------------------------------"
echo "Activating New Kernel on $REMOTE_USER@$REMOTE_HOST"
echo "--------------------------------------------------------"

# Read password safely
read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " SSHPASS
export SSHPASS
echo ""

# Update extlinux.conf
echo "Updating bootloader config to use $NEW_KERNEL..."
REMOTE_COMMANDS="
echo '$SSHPASS' | sudo -S -p '' true && 
echo '-> Backing up extlinux.conf...' && 
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak2 && 
echo '-> Updating Kernel path...' && 
sudo sed -i 's|kernel /boot/vmlinuz-linux-aarch64-rockchip-bsp6.1-joshua-git|kernel $NEW_KERNEL|' /boot/extlinux/extlinux.conf && 
echo '-> Updating Initrd path (if needed)...' && 
echo '   (Assuming existing initrd is compatible or new one was not generated. If boot fails, we revert.)'
"
# Note: Usually initrd needs to match the kernel modules. 
# The user's 'deploy_to_radxa.sh' didn't generate a new initrd.
# However, since we copied modules to /lib/modules/6.1.84..., and the version string matches, 
# the existing initrd *might* work if it only contains basic boot modules.
# But ideally we should generate a new initrd.
# Arch Linux uses 'mkinitcpio'.

GENERATE_INITRD_CMD="
echo '-> Generating new initrd for kernel $NEW_KERNEL...' && 
sudo mkinitcpio -k 6.1.84-g2e8040ec92f8 -g /boot/initramfs-linux-uconsole.img && 
sudo sed -i 's|initrd /boot/initramfs-linux-aarch64-rockchip-bsp6.1-joshua-git.img|initrd /boot/initramfs-linux-uconsole.img|' /boot/extlinux/extlinux.conf
"

sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_COMMANDS $GENERATE_INITRD_CMD"

echo "--------------------------------------------------------"
echo "Kernel Activated!"
echo "Please reboot your device manually: ssh $REMOTE_USER@$REMOTE_HOST 'sudo reboot'"
echo "--------------------------------------------------------"

unset SSHPASS

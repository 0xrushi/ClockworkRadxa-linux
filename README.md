
# Quick Start (Pre-Built Image)

If you want to skip the build process, use this pre-built and configured Arch Linux image:

- **Download:** [MEGA link](https://mega.nz/file/qsA3GTAK#Vn-Ov_UjJACoXncOFeFo2zNVIY9TEAe3-5tkVLVe14Q) (.gz compressed)
- **Requirements:** At least a **64GB SD card or eMMC** (image was created on 64GB)
- **Flash to card** and use


# Building Arch linux image for Radxa CM5 for u-Console

<img width="950" height="724" alt="image" src="https://github.com/user-attachments/assets/fe0a377f-9d77-44d4-9b34-ad3f1924b75e" />


### Initial Setup

1. Download the [base Arch Linux image from kwankiu's archlinux-installer](https://github.com/kwankiu/archlinux-installer/releases)
2. Flash the image to an SD card or eMMC adapter
3. Boot the image on a **CM5-CM4IO board** (not the uConsole yet)
4. Install Arch Linux and perform any initial configuration
5. Power down and transfer the SD card/eMMC to your uConsole

### Network Setup

Once you insert the SD card into the uConsole and power it on:

1. **Plug in the Ethernet module** — Connect the USB Ethernet adapter with an ethernet cable
2. **Find the IP address** — Use a network scanner to detect the device:
   - **Android:** [Fing app](https://play.google.com/store/apps/details?id=com.overlook.android.fing)
   - **Other options:** `nmap`, `arp-scan`, or your router's DHCP client list
3. **SSH into the uConsole:**
   ```bash
   ssh archuser@<ip-address>
   ```

At this point, your uConsole will boot but the display will be blank (backlight on, no image).

## Prerequisites for Display Fix

To fix the display, you'll need:

- Arch Linux ARM installation running on uConsole (boots, no display)
- SSH access from another computer
- Working Debian image file for uConsole CM5 (`.img` file)
- Computer with tools to mount the Debian image

## Build + Deploy a Fixed Kernel (panel driver as module)

The uConsole display stays blank if `CONFIG_DRM_PANEL_CWU50` is built into the kernel (`=y`). Rebuild the kernel with it as a module (`=m`) and deploy the new kernel + modules.

### 0) Build machine prerequisites

Install an AArch64 cross-compiler on your build machine:

```bash
# Arch
sudo pacman -S aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils

# Debian/Ubuntu
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

### 1) Kernel config change

In the kernel source tree root (`.config`), set these:

```text
CONFIG_REGMAP_I2C=y
CONFIG_INPUT_AXP20X_PEK=y
CONFIG_CHARGER_AXP20X=m
CONFIG_BATTERY_AXP20X=m
CONFIG_AXP20X_POWER=m
CONFIG_MFD_AXP20X=y
CONFIG_MFD_AXP20X_I2C=y
CONFIG_REGULATOR_AXP20X=y
CONFIG_DRM_PANEL_CWD686=m
CONFIG_DRM_PANEL_CWD686_CM3=m
CONFIG_DRM_PANEL_CWU50=m
CONFIG_DRM_PANEL_CWU50_CM3=m
CONFIG_BACKLIGHT_OCP8178=m
CONFIG_AXP20X_ADC=m
CONFIG_TI_ADC081C=m
CONFIG_CRYPTO_LIB_ARC4=y
CONFIG_CRC_CCITT=y
```

I have already updated those values in `.config` and they are in this branch.

### 2) One-line driver build fix

When built as a module, the CWU50 panel driver needs an extra include. From the kernel source root:

```bash
sed -i '/#include <linux\/module.h>/a #include <video/mipi_display.h>' \
  drivers/gpu/drm/panel/panel-cwu50.c
```

### 3) Build (Image + modules + dtbs)

From the kernel source root:

```bash
# prepare the .config file
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Cross-compile the ARM64 Linux kernel, build the kernel image, build all loadable modules, and build all device tree blobs — using all CPU cores
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image modules dtbs
```

### 4) Stage modules (modules_install)

```bash
mkdir -p ~/cm5-kernel-staging
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=$HOME/cm5-kernel-staging modules_install
```

### 5) Copy kernel + modules to the uConsole

Use the deploy script (edit `REMOTE_HOST` / `MODULES_DIR` at the top if needed):

```bash
./deploy-scripts/deploy_to_radxa.sh
```

Or manually (replace `<uconsole-ip>`), run from the kernel source root:

```bash
# Kernel image
scp arch/arm64/boot/Image archuser@<uconsole-ip>:/tmp/Image
ssh archuser@<uconsole-ip> 'sudo cp /tmp/Image /boot/vmlinuz-linux-uconsole'

# Modules
rsync -av ~/cm5-kernel-staging/lib/modules/ archuser@<uconsole-ip>:/tmp/new-modules/
ssh archuser@<uconsole-ip> 'sudo cp -r /tmp/new-modules/* /lib/modules/ && rm -rf /tmp/new-modules'
```

### 6) On uConsole: depmod + initramfs

SSH into the uConsole and use the new kernel version shown by `ls /lib/modules/`:

```bash
ssh archuser@<uconsole-ip>
ls /lib/modules/

# get the kernel version
uname -r

sudo depmod -a <your-kernel-version>
sudo mkinitcpio -k <your-kernel-version> -g /boot/initramfs-linux-uconsole.img
```

## Installation

### Step 1: Deploy the DTB

The kernel build produces `rk3588s-radxa-cm5-uconsole-merged.dtb` directly in the source tree — it already has the CWU50 panel, AXP20x PMIC, and DSI1 nodes baked in. This is confirmed working. You do **not** need the Debian image extraction.

Use the deploy script from the kernel source root:

```bash
./deploy-scripts/deploy_dtb_overlays.sh
```

This copies the built DTB to `/boot/dtbs/uconsole-cm5/rk3588s-radxa-cm5-uconsole-merged.dtb` on the device.

To verify the DTB is correct before deploying (on the build machine, requires `dtc`):

```bash
# Inspect the DTB as readable text
dtc -I dtb -O dts \
  arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-merged.dtb \
  2>/dev/null | grep -E "cwu50|dsi@fde30000|status"

# Quick spot-checks with fdtget (install with: sudo pacman -S dtc)
fdtget arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-merged.dtb \
  /dsi@fde30000/panel@0 compatible
# Should output: cw,cwu50

fdtget arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-merged.dtb \
  /dsi@fde30000 status
# Should output: okay
```

<details>
<summary>Fallback: Extract DTB from Debian image (only if built DTB doesn't work)</summary>

**On your build machine:**

Create a mount point and find partition offsets:
```bash
sudo mkdir -p /mnt/debian-img
fdisk -l /path/to/debian-image.img
```

Look for the Linux partition (usually the largest). Note the "Start" sector number. Multiply by 512 to get the byte offset (e.g., 32768 × 512 = 16777216).

Mount the image:
```bash
sudo mount -o loop,offset=<calculated_offset> /path/to/debian-image.img /mnt/debian-img
```

Extract the base DTB:
```bash
ls /mnt/debian-img/usr/lib/linux-image-6.1.84+/rockchip/
cp /mnt/debian-img/usr/lib/linux-image-6.1.84+/rockchip/rk3588s-radxa-cm5-rpi-cm4-io.dtb ~/original-debian.dtb
```

Extract overlay files:
```bash
mkdir -p ~/debian-dtbo
cp /mnt/debian-img/boot/dtbo/axp20x.dtbo ~/debian-dtbo/
cp /mnt/debian-img/boot/dtbo/cwu50_panel.dtbo ~/debian-dtbo/
cp /mnt/debian-img/boot/dtbo/displaystuff.dtbo ~/debian-dtbo/
```

Unmount:
```bash
sudo umount /mnt/debian-img
```

Transfer files to uConsole:
```bash
scp ~/original-debian.dtb archuser@<uconsole-ip>:~/original-debian.dtb
scp -r ~/debian-dtbo/ archuser@<uconsole-ip>:~/debian-dtbo/
```

**On the uConsole (via SSH):**

Ensure `fdtoverlay` is installed:
```bash
sudo pacman -S dtc
```

Merge the base DTB with overlays in the correct order:
```bash
fdtoverlay \
  -i ~/original-debian.dtb \
  -o ~/debian-merged.dtb \
  ~/debian-dtbo/axp20x.dtbo \
  ~/debian-dtbo/cwu50_panel.dtbo \
  ~/debian-dtbo/displaystuff.dtbo
```

Verify the merge:
```bash
fdtget ~/debian-merged.dtb /dsi@fde30000/panel@0 compatible
# Should output: cw,cwu50

fdtget ~/debian-merged.dtb /dsi@fde30000 status
# Should output: okay

fdtget ~/debian-merged.dtb /phy@fedb0000 status
# Should output: okay
```

Install the merged DTB:
```bash
sudo cp ~/debian-merged.dtb /boot/dtbs/uconsole-cm5/debian-merged.dtb
```

Then point `extlinux.conf` at `/boot/dtbs/uconsole-cm5/debian-merged.dtb` instead.

</details>

---

### Step 2: Update Boot Configuration

Back up current configuration:
```bash
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
```

Edit the configuration:
```bash
sudo nano /boot/extlinux/extlinux.conf
```

Update the `fdt` line to point to the newly deployed DTB (keep everything else as-is):
```
label uconsole-linux-uconsole
    menu label uConsole (vmlinuz-linux-uconsole)
    kernel /boot/vmlinuz-linux-uconsole
    initrd /boot/initramfs-linux-uconsole.img
    fdt /boot/dtbs/uconsole-cm5/rk3588s-radxa-cm5-uconsole-merged.dtb
    append root=UUID=b6416d3c-ad04-4289-a5d1-8c02070ba8a1 earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 console=tty1 consoleblank=0 loglevel=7 panic=10 rootwait rw init=/sbin/init rootfstype=ext4 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 irqchip.gicv3_pseudo_nmi=0 switolb=1 coherent_pool=2M fbcon=rotate:1
```

**Critical notes:**
- **Do NOT include an `fdtoverlays` line** — overlays are already baked into the DTB
- The initramfs must be rebuilt for the new kernel version before rebooting (see step 6)

Save and exit (Ctrl+O, Enter, Ctrl+X in nano).

### Step 3: Reboot

```bash
sudo reboot
```

You should now see the SDDM login screen on your uConsole display.

## Troubleshooting

### Screen is still blank

SSH back in and verify the system booted:
```bash
ssh archuser@<uconsole-ip>
```

Check kernel logs for display errors:
```bash
dmesg | grep -i 'dsi\|panel\|cwu50\|drm'
```

Verify your boot configuration:
- Ensure the `fdt` path in `extlinux.conf` is correct
- Ensure there is NO `fdtoverlays` line

Restore the backup if needed:
```bash
sudo cp /boot/extlinux/extlinux.conf.bak /boot/extlinux/extlinux.conf
```

### System doesn't boot at all

Extract the SD card/eMMC and mount it on another computer, then manually restore `extlinux.conf.bak`.

### Finding your UUID

```bash
blkid
```

### Finding kernel and initrd filenames

```bash
ls /boot/vmlinuz*
ls /boot/initramfs*
```

## Misc: Networking

### Ethernet

Ethernet works out of the box via the USB Ethernet adapter — no configuration needed. Plug it in and the device will get a DHCP address.

### WiFi (NetworkManager fix)

NetworkManager fails to start on boot with `status=226/NAMESPACE` because its service unit has `ProtectSystem=true`, which makes systemd try to bind-mount `/efi` as read-only. This device has no `/efi` directory (it uses extlinux, not UEFI), so the mount fails.

Fix with a drop-in override:

```bash
sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
sudo tee /etc/systemd/system/NetworkManager.service.d/no-protect-system.conf << 'EOF'
[Service]
ProtectSystem=false
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now NetworkManager
```

This persists across reboots. After running it, WiFi can be managed normally with `nmcli` or `nmtui`.

## Key Files Reference

| File | Purpose |
|------|---------|
| `arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-uconsole-merged.dtb` | Built-from-source DTB with panel/PMIC/DSI nodes (preferred) |
| `/boot/dtbs/uconsole-cm5/rk3588s-radxa-cm5-uconsole-merged.dtb` | Installed copy used at boot |
| `~/original-debian.dtb` | (Fallback) Base DTB extracted from Debian image |
| `~/debian-dtbo/*.dtbo` | (Fallback) Overlay files from Debian image |
| `~/debian-merged.dtb` | (Fallback) Merged DTB from Debian base + overlays |
| `/boot/extlinux/extlinux.conf` | Boot configuration |
| `/boot/extlinux/extlinux.conf.bak` | Configuration backup |

## Credits & References

- **ak-rex** — [Debian image for uConsole](https://github.com/ak-rex)
- **kwankiu** — [Arch Linux installer for Radxa CM5](https://github.com/kwankiu/archlinux-installer/releases)
- **Radxa CM5-CM4IO Board** — [Amazon link (reference)](https://www.amazon.com/Raspberry-Standard-Color-Coded-Evaluating-Integrated/dp/B095CSRWXS/)
- **Official Radxa CM5-IO Board** — [radxa.com](https://radxa.com/products/io-board/cm5-io-board/)

Note: The uConsole motherboard uses the CM5-CM4IO pinout, so using a compatible CM5-CM4IO board may help with installation and compatibility.
---

============

Linux kernel

============

There are several guides for kernel developers and users. These guides can
be rendered in a number of formats, like HTML and PDF. Please read
Documentation/admin-guide/README.rst first.

In order to build the documentation, use ``make htmldocs`` or
``make pdfdocs``.  The formatted documentation can also be read online at:

    https://www.kernel.org/doc/html/latest/

There are various text files in the Documentation/ subdirectory,
several of them using the Restructured Text markup notation.

Please read the Documentation/process/changes.rst file, as it contains the
requirements for building and running the kernel, and information about
the problems which may result by upgrading your kernel.

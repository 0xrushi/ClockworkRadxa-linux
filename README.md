
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

## Installation

### Step 1: Extract Files from Debian Image

**On your other computer (or via SSH):**

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

### Step 2: Merge the DTB with Overlays

**On the uConsole (via SSH):**

Ensure `fdtoverlay` is installed:
```bash
which fdtoverlay
```

If not found, install it:
```bash
sudo pacman -S dtc
```

Merge the base DTB with all overlays in the correct order:
```bash
fdtoverlay \
  -i ~/original-debian.dtb \
  -o ~/test-merged.dtb \
  ~/debian-dtbo/axp20x.dtbo \
  ~/debian-dtbo/cwu50_panel.dtbo \
  ~/debian-dtbo/displaystuff.dtbo
```

Verify the merge (optional but recommended):
```bash
# Check that the panel node exists
fdtget ~/test-merged.dtb /dsi@fde30000/panel@0 compatible
# Should output: cw,cwu50

# Check DSI1 is enabled
fdtget ~/test-merged.dtb /dsi@fde30000 status
# Should output: okay

# Check DCPHY1 is enabled
fdtget ~/test-merged.dtb /phy@fedb0000 status
# Should output: okay
```

### Step 3: Install the Merged DTB

Copy to boot partition:
```bash
sudo cp ~/test-merged.dtb /boot/dtbs/uconsole-cm5/test-merged.dtb
```

### Step 4: Update Boot Configuration

Back up current configuration:
```bash
sudo cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.bak
```

Edit the configuration:
```bash
sudo nano /boot/extlinux/extlinux.conf
```

Update it to look like this (adjust UUID, kernel, and initrd paths for your system):
```
label uconsole
menu label uConsole CM5
kernel /boot/vmlinuz-linux-uconsole
initrd /boot/initramfs-linux-aarch64-rockchip-bsp6.1-joshua-git.img
fdt /boot/dtbs/uconsole-cm5/test-merged.dtb
append root=UUID=b6416d3c-ad04-4289-a5d1-8c02070ba8a1 earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 console=tty1 consoleblank=0 loglevel=7 panic=10 rootwait rw init=/sbin/init rootfstype=ext4
```

**Critical notes:**
- The `fdt` line must point to your newly merged DTB
- **Do NOT include an `fdtoverlays` line**—overlays are already merged into the DTB
- Adding `fdtoverlays` would apply them twice and break the display

Save and exit (Ctrl+O, Enter, Ctrl+X in nano).

### Step 5: Reboot

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

## Key Files Reference

| File | Purpose |
|------|---------|
| `~/original-debian.dtb` | Base DTB extracted from working Debian image |
| `~/debian-dtbo/*.dtbo` | Overlay files from Debian image |
| `~/test-merged.dtb` | Properly merged DTB (base + overlays) |
| `/boot/dtbs/uconsole-cm5/test-merged.dtb` | Installed copy used at boot |
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

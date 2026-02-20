# USB WiFi Setup for uConsole CM5

The onboard Radxa CM5 WiFi does not work on the uConsole. You need a USB WiFi
adapter connected via the USB-C port.

---

## Step 1: Fix NetworkManager

NetworkManager fails to start out of the box because its service unit uses
`ProtectSystem=true`, which tries to bind-mount `/efi` read-only. This device
has no `/efi` directory (it uses extlinux, not UEFI), so the mount fails.

```bash
sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
sudo tee /etc/systemd/system/NetworkManager.service.d/no-protect-system.conf << 'EOF'
[Service]
ProtectSystem=false
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now NetworkManager
```

Verify it's running:
```bash
systemctl status NetworkManager
```

---

## Step 2: Firmware

**All Mediatek firmware is already installed** via the `linux-firmware` package.
The following chipsets are confirmed present in `/lib/firmware/mediatek/`:

| Chipset | WiFi Standard | Firmware files present |
|---------|--------------|------------------------|
| MT7925  | WiFi 7       | `mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin`, `mt7925/WIFI_RAM_CODE_MT7925_1_1.bin`, `mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin` |
| MT7922  | WiFi 6E      | `WIFI_MT7922_patch_mcu_1_1_hdr.bin`, `WIFI_RAM_CODE_MT7922_1.bin`, `BT_RAM_CODE_MT7922_1_1_hdr.bin` |
| MT7921  | WiFi 6/6E    | `WIFI_MT7961_patch_mcu_1_2_hdr.bin`, `WIFI_RAM_CODE_MT7961_1.bin`, `BT_RAM_CODE_MT7961_1_2_hdr.bin` |
| MT7921  | WiFi 6/6E    | `WIFI_MT7961_patch_mcu_1a_2_hdr.bin`, `WIFI_RAM_CODE_MT7961_1a.bin`, `BT_RAM_CODE_MT7961_1a_2_hdr.bin` |
| MT7612  | WiFi 5       | `mt7662u.bin`, `mt7662u_rom_patch.bin` |
| MT7610  | WiFi 5       | `mt7610u.bin` |
| MT7601  | WiFi 4       | `mt7601u.bin` |

No manual firmware installation needed. Just plug in your adapter and the
kernel will load the correct firmware automatically.

If for some reason firmware is missing or needs updating, refer to:
[@morrownr's USB-WiFi firmware guide](https://github.com/morrownr/USB-WiFi/blob/main/home/How_to_Install_Firmware_for_Mediatek_based_USB_WiFi_adapters.md)

---

## Step 3: Verify adapter is detected

Plug in your USB WiFi adapter and check it's recognized:

```bash
# Check USB device is seen
lsusb

# Check kernel loaded the driver and firmware
dmesg | grep -i 'mt76\|mt79\|firmware' | tail -20

# Check a wireless interface appeared
ip link
iw dev
```

If the adapter shows up in `lsusb` but not in `iw dev`, the firmware may be
missing — check `dmesg` for firmware load errors.

---

## Step 4: Connect to WiFi

Use `nmtui` for a simple terminal UI:

```bash
nmtui
```

Or `nmcli` from the command line:

```bash
# List available networks
nmcli device wifi list

# Connect to a network
nmcli device wifi connect "SSID" password "yourpassword"

# Check status
nmcli connection show
```

---

## Troubleshooting

**Adapter not showing as a network interface:**
```bash
dmesg | grep -i 'mt76\|mt79\|usb\|firmware'
```

**Check firmware version loaded:**
```bash
# Replace wlan0 with your interface name
ethtool -i wlan0
```

**Install ethtool/iw if missing:**
```bash
sudo pacman -S ethtool iw
```

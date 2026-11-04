#!/usr/bin/env bash
#
# Collect everything needed for a COMPATIBILITY.md row and a useful bug report.
# Read-only: no root, no network, no writes outside /tmp.
#
#   ./scripts/report-machine.sh            # human readable + ready-to-paste row
#   ./scripts/report-machine.sh --save DIR # also write the raw logs into DIR
#
# The first line of output is a markdown table row - paste it into
# COMPATIBILITY.md (or into an issue) and fill in the blanks.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh" 2>/dev/null || true

SAVE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--save) SAVE="${2:-}"; shift 2 ;;
		-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- identity --
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\n')
[ -n "$vendor$model" ] || { vendor=unknown; model=unknown; }
machine="$vendor $model"
[ "$machine" = "unknown unknown" ] && machine="(dmi unreadable)"
krel=$(uname -r)
# shellcheck source=/dev/null
distro=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-unknown}")

# ------------------------------------------------------------------ hardware --
pci_line=$(lspci -nn 2>/dev/null | grep -i '17cb' | head -1)
usb_line=$(lsusb 2>/dev/null | grep -i '2c7c' | head -1)
mod_ids=""
[ -n "$pci_line" ] && mod_ids="17cb:1107"
[ -n "$usb_line" ] && mod_ids="${mod_ids:+$mod_ids / }2c7c:0130"
[ -n "$mod_ids" ] || mod_ids="(no card visible)"

# ------------------------------------------------------------------- drivers --
ath12k_path=$(modinfo -F filename ath12k 2>/dev/null || true)
btusb_path=$(modinfo -n btusb 2>/dev/null || true)
btusb_ids=$(modinfo btusb 2>/dev/null | grep -c 'v2C7Cp0130' || true)
fw_wifi=no; [ -f /lib/firmware/ath12k/WCN7850/hw2.0/amss.bin ] && fw_wifi=yes
fw_bt=no;   [ -f /lib/firmware/qca/rampatch_usb_00190200.bin ] && fw_bt=yes

# ---------------------------------------------------------------- interfaces --
wlan=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
ssid=""
if [ -n "$wlan" ] && have iw; then
	ssid=$(iw dev "$wlan" link 2>/dev/null | awk -F': ' '/SSID/{print $2; exit}')
fi
hci=$(lsusb >/dev/null 2>&1; bluetoothctl list 2>/dev/null | awk '{print $2; exit}')
[ -n "$hci" ] || hci=$(find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -1)
band6="unknown"
if have iw; then
	if iw phy 2>/dev/null | grep -q 'Band 4'; then band6="listed"; else band6="absent"; fi
fi

# -------------------------------------------------------------------- states --
wifi_state="❌"
if [ -n "$wlan" ]; then
	if [ -n "$ssid" ]; then wifi_state="✅ $ssid"; else wifi_state="⚠️ $wlan up, not associated"; fi
fi
bt_state="❌"
if [ -n "$hci" ]; then bt_state="✅ $(basename "$hci")"; fi

sb="disabled"
if [ -d /sys/firmware/efi ] && have mokutil; then
	mokutil --sb-state 2>/dev/null | grep -qi enabled && sb="enabled"
fi

# --------------------------------------------------------------------- row ---
row="| $machine | NCM865 · $mod_ids | $distro · $krel | $wifi_state | $bt_state | 6 GHz: $band6 · SB: $sb |"

echo "=== COMPATIBILITY.md row (paste this) ==="
echo "$row"
echo
echo "=== detail ==="
printf '  machine      : %s\n' "$machine"
printf '  distro       : %s\n' "$distro"
printf '  kernel       : %s\n' "$krel"
printf '  pci          : %s\n' "${pci_line:-(none)}"
printf '  usb          : %s\n' "${usb_line:-(none)}"
printf '  ath12k       : %s\n' "${ath12k_path:-missing}"
printf '  btusb        : %s (2c7c aliases: %s)\n' "${btusb_path:-missing}" "$btusb_ids"
printf '  firmware     : wifi=%s bt=%s\n' "$fw_wifi" "$fw_bt"
printf '  wlan / ssid  : %s / %s\n' "${wlan:-(none)}" "${ssid:-(none)}"
printf '  hci          : %s\n' "${hci:-(none)}"
printf '  6 GHz band   : %s\n' "$band6"
printf '  secure boot  : %s\n' "$sb"

if [ -n "$SAVE" ]; then
	mkdir -p "$SAVE" || exit 1
	{
		echo "$row"; echo; echo "machine=$machine"; echo "distro=$distro"
		echo "kernel=$krel"; echo "pci=$pci_line"; echo "usb=$usb_line"
	} > "$SAVE/summary.txt"
	{
		lspci -nn 2>/dev/null; echo; lsusb 2>/dev/null
		echo; modinfo ath12k 2>/dev/null | head -20
		echo; modinfo btusb 2>/dev/null | head -20
	} > "$SAVE/hardware.txt"
	( dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || echo "run: sudo dmesg" ) |
		grep -iE 'ath12k|btusb|bluetooth|firmware' | tail -80 > "$SAVE/kernel-log.txt"
	iw dev > "$SAVE/iw-dev.txt" 2>&1
	rfkill list > "$SAVE/rfkill.txt" 2>&1
	bluetoothctl list > "$SAVE/bluetooth.txt" 2>&1
	echo
	echo "saved to $SAVE/ (summary.txt, hardware.txt, kernel-log.txt, iw-dev.txt, rfkill.txt, bluetooth.txt)"
fi

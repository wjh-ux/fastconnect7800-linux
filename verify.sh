#!/usr/bin/env bash
#
# Read-only health check for the FastConnect 7800 under Linux.
#
#   ./verify.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

line() { printf '%s\n' "--------------------------------------------------------------"; }
ask()  { "$@" 2>/dev/null || echo "(unavailable)"; }

echo "FastConnect 7800 (WCN7850 / NCM865) status"
echo "host $(hostname)   kernel $(uname -r)   $(distro_id) $(distro_ver)"
line

echo "1) hardware visible to this kernel"
ask sh -c "lspci -nn | grep -i 17cb"  || true
ask sh -c "lsusb | grep -i 2c7c"     || true
lspci -nn 2>/dev/null | grep -qi 17cb:1107 && ok "WiFi PCI 17cb:1107 present" || warn "WiFi PCI 17cb:1107 NOT visible"
lsusb 2>/dev/null | grep -qi 2c7c:0130 && ok "BT USB 2c7c:0130 present"       || warn "BT USB 2c7c:0130 NOT visible"
line

echo "2) drivers"
printf '  ath12k : %s\n' "$(modinfo -F filename ath12k 2>/dev/null || echo missing)"
printf '  btusb  : %s\n' "$(modinfo -n btusb 2>/dev/null || echo missing)"
btusb_has_id && ok "btusb advertises 2c7c:0130" || warn "btusb does NOT advertise 2c7c:0130"
ask sh -c "lsmod | grep -E 'ath12k|btusb|btqca|bluetooth'"
line

echo "3) firmware"
for f in ath12k/WCN7850/hw2.0/amss.bin ath12k/WCN7850/hw2.0/m3.bin \
         ath12k/WCN7850/hw2.0/board-2.bin qca/rampatch_usb_00190200.bin \
         qca/nvm_usb_00190200.bin; do
	if [ -f "/lib/firmware/$f" ]; then ok "/lib/firmware/$f"
	else warn "/lib/firmware/$f MISSING"; fi
done
line

echo "4) interfaces / radios"
ask sh -c "iw dev"
ask sh -c "rfkill list"
ask sh -c "bluetoothctl list"
ask sh -c "hciconfig -a"
line

echo "5) kernel log (needs root for dmesg on hardened systems)"
if dmesg 2>/dev/null | grep -qiE 'ath12k|btusb'; then
	dmesg 2>/dev/null | grep -iE 'ath12k|btusb|bluetooth' | tail -25
else
	echo "  (nothing, or dmesg needs root:  sudo dmesg | grep -iE 'ath12k|btusb')"
fi
line

echo "6) Secure Boot"
if secboot_enabled; then
	warn "Secure Boot enabled - an out-of-tree btusb must be signed AND its key enrolled"
	mokutil --sb-state 2>/dev/null || true
	mokutil --test-key /var/lib/shim-signed/mok/MOK.der 2>/dev/null || true
else
	ok "Secure Boot disabled - out-of-tree modules load without signing"
fi
line

echo
echo "Green here + a card in '1)' means the driver side is done."
echo "Card missing in '1)' is a hardware/VM problem, not a driver problem."

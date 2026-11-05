#!/bin/sh
#
# install-openwrt.sh - FastConnect 7800 (WCN7850 / NCM865) on OpenWrt / iStoreOS
#
#   ./install-openwrt.sh            # WiFi 7 via ath12k + firmware
#   ./install-openwrt.sh --with-bt  # also the Bluetooth packages
#
# Run as root on the router. BusyBox sh only - no bashisms.
#
set -eu

WITH_BT=0
for a in "$@"; do
	case "$a" in
		--with-bt) WITH_BT=1 ;;
		-h|--help) sed -n '2,9p' "$0"; exit 0 ;;
		*) echo "unknown option: $a" >&2; exit 2 ;;
	esac
done

HERE=$(cd "$(dirname "$0")" && pwd)

[ -f /etc/openwrt_release ] || {
	echo "not an OpenWrt/iStoreOS system (/etc/openwrt_release missing)" >&2
	exit 1
}
# shellcheck source=/dev/null
. /etc/openwrt_release

KREL=$(uname -r)
KMM=$(echo "$KREL" | cut -d. -f1,2)
echo "==> ${DISTRIB_DESCRIPTION:-OpenWrt}  kernel $KREL  $(uname -m)"

case "$KMM" in
5.*)
	echo "!! kernel $KMM: ath12k does not exist before 6.6 - this card cannot work here." >&2
	echo "   Use OpenWrt 24.10 (6.6) or a snapshot (6.18) on this machine." >&2
	exit 1
	;;
esac

echo "==> opkg update"
opkg update >/dev/null 2>&1 || echo "   (opkg update failed - check WAN/feeds, continuing)"

install_pkg() {
	if opkg list-installed 2>/dev/null | grep -q "^$1 "; then
		echo "   already installed: $1"
		return 0
	fi
	if opkg install "$1" >/dev/null 2>&1; then
		echo "   installed: $1"
	else
		echo "   FAILED to install: $1"
		return 1
	fi
}

MISSING=0
echo "==> WiFi packages"
install_pkg kmod-ath12k || MISSING=1
install_pkg ath12k-firmware-wcn7850 || MISSING=1
opkg list-installed 2>/dev/null | grep -q '^iw ' || install_pkg iw >/dev/null 2>&1 || true

if [ "$MISSING" -ne 0 ]; then
	echo
	echo "!! ath12k packages are not in this feed." >&2
	echo "   iStoreOS / older builds often ship an OpenWrt branch without ath12k;" >&2
	echo "   check with:  opkg list | grep -i ath12k" >&2
	echo "   If they are absent you need a custom build (see docs/OPENWRT.md)." >&2
fi

echo "==> checking the card"
if lspci -nn 2>/dev/null | grep -qi '17cb'; then
	lspci -nn | grep -i '17cb'
else
	echo "   no 17cb device visible (card not in this box, or PCIe slot off)" >&2
fi
if lsmod | grep -q '^ath12k'; then
	echo "   ath12k loaded"
elif modprobe ath12k 2>/dev/null; then
	echo "   ath12k loaded"
else
	echo "   ath12k NOT loaded" >&2
fi

echo "==> firmware"
for f in ath12k/WCN7850/hw2.0/amss.bin ath12k/WCN7850/hw2.0/m3.bin ath12k/WCN7850/hw2.0/board-2.bin; do
	if [ -f "/lib/firmware/$f" ]; then echo "   ok   /lib/firmware/$f"; else echo "   MISSING /lib/firmware/$f" >&2; fi
done

if [ "$WITH_BT" = 1 ]; then
	echo "==> Bluetooth packages"
	install_pkg kmod-btusb || true
	install_pkg bluez-daemon || true
	install_pkg bluez-utils || true

	echo "==> Bluetooth firmware (OpenWrt does not package these)"
	for f in qca/rampatch_usb_00190200.bin qca/nvm_usb_00190200.bin; do
		if [ -f "/lib/firmware/$f" ]; then
			echo "   ok   /lib/firmware/$f"
		elif [ -f "$HERE/firmware/$f" ]; then
			mkdir -p /lib/firmware/qca
			cp -f "$HERE/firmware/$f" "/lib/firmware/$f"
			echo "   copied $f from the bundle"
		else
			echo "   MISSING /lib/firmware/$f - copy it from firmware/qca/ of this repo" >&2
		fi
	done

	echo "==> does this kernel's btusb know 2c7c:0130?"
	if modinfo btusb 2>/dev/null | grep -qi 'v2C7Cp0130'; then
		echo "   yes (kernel >= 6.13) - nothing to patch"
	else
		echo "   NO - this kernel is older than 6.13." >&2
		echo "   Either build a snapshot (6.18) or apply" >&2
		echo "   openwrt/patches/010-btusb-wcn785x-usb-ids.patch to your build tree." >&2
	fi
fi

echo
echo "WiFi is now a normal OpenWrt radio. Check it with:"
echo "   iw dev                      # phy0 should appear"
echo "   iw phy | grep -i band       # Band 1 / 2 / 4"
echo "   wifi status"
echo
echo "AP config example (2.4 GHz; change band/frequency for 5 or 6 GHz):"
cat <<'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option path '<from: iw dev | grep phy>'
	option band '2g'
	option channel '6'
	option htmode 'EHT20'
	option country 'CN'
	option cell_density '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'MyWiFi7'
	option encryption 'sae'
	option key '<password>'
EOF
echo
echo "6 GHz (needs hostapd with 6 GHz support, a regdb that allows it and"
echo "'option country' set): option band '6g' / channel '37'."

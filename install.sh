#!/usr/bin/env bash
#
# FastConnect 7800 (WCN7850 / NCM865) - WiFi + Bluetooth on Ubuntu / Debian
#
#   sudo ./install.sh
#
# What it does
#   1. installs the firmware the card needs (ath12k WCN7850 + QCA USB BT blobs)
#   2. checks the running kernel can host the ath12k driver (>= 6.8)
#   3. makes btusb recognise USB 2c7c:0130 (NCM865 Bluetooth)
#        - if the kernel already knows the ID: nothing to do
#        - 6.8.x kernels: DKMS module from the bundled source
#        - otherwise: rebuild btusb from the distro's own kernel source
#   4. prints what still needs a human (Secure Boot enrolment, reboot, VM setup)
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

FC_DKMS_NAME=btusb-fastconnect
FC_DKMS_VER=1.0

install_pkgs() {
	if [ "${FC_OFFLINE:-0}" = "1" ]; then
		warn "offline mode - not running apt ($*)"
		return 0
	fi
	command -v apt-get >/dev/null || die "this script supports apt based distros only"
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null || die "apt-get install failed: $*"
}

# --------------------------------------------------------------- kernel ------
check_kernel() {
	local id; id=$(distro_id)
	info "kernel: $(uname -r)"

	if kernel_at_least 6 8; then
		ok "kernel is new enough for ath12k / WCN7850"
		return
	fi

	warn "kernel $(uname -r) is too old for this card (ath12k needs >= 6.8)"
	case "$id" in
	ubuntu)
		if [ "$(distro_ver)" = "22.04" ]; then
			info "installing the 6.8 HWE kernel"
			install_pkgs linux-generic-hwe-22.04
		else
			info "installing the HWE kernel"
			install_pkgs "linux-generic-hwe-$(distro_ver)"
		fi
		warn "reboot into the new kernel, then run this script again"
		exit 0
		;;
	debian)
		info "adding bookworm-backports and installing kernel 6.12"
		echo "deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware" \
			> /etc/apt/sources.list.d/fc-backports.list
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -t bookworm-backports \
			linux-image-amd64 linux-headers-amd64 >/dev/null || die "backports kernel install failed"
		warn "reboot into the 6.12 kernel, then run this script again"
		exit 0
		;;
	*)
		die "unknown distro '$id' - install a kernel >= 6.8 first"
		;;
	esac
}

# ---------------------------------------------------------------- btusb ------
install_btusb_dkms() {
	local src="/usr/src/$FC_DKMS_NAME-$FC_DKMS_VER"

	if [ "${FC_NO_DKMS:-0}" = "1" ]; then
		warn "FC_NO_DKMS=1 - skipping dkms, building a one-shot module"
		build_btusb_plain
		return
	fi
	if ! command -v dkms >/dev/null; then
		warn "dkms not installed - building a one-shot module instead"
		build_btusb_plain
		return
	fi

	info "building the patched btusb module with DKMS (kernel $(kver_mm))"
	install_pkgs dkms build-essential "linux-headers-$(uname -r)"

	rm -rf "$src"
	mkdir -p "$src"
	cp "$HERE"/btusb/src-6.8/* "$src"/

	cat > "$src/dkms.conf" <<EOF
PACKAGE_NAME="$FC_DKMS_NAME"
PACKAGE_VERSION="$FC_DKMS_VER"
BUILT_MODULE_NAME[0]="btusb"
BUILT_MODULE_LOCATION[0]="."
DEST_MODULE_LOCATION[0]="/updates"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/$FC_DKMS_NAME/$FC_DKMS_VER/build modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/$FC_DKMS_NAME/$FC_DKMS_VER/build clean"
AUTOINSTALL="yes"
EOF

	dkms remove "$FC_DKMS_NAME/$FC_DKMS_VER" --all >/dev/null 2>&1 || true
	dkms add "$src" >/dev/null 2>&1 || die "dkms add failed"
	dkms build "$FC_DKMS_NAME/$FC_DKMS_VER" || die "dkms build failed - see /var/lib/dkms/$FC_DKMS_NAME/$FC_DKMS_VER/build/make.log"
	dkms install --force "$FC_DKMS_NAME/$FC_DKMS_VER" || die "dkms install failed"

	depmod -a
	update-initramfs -u >/dev/null 2>&1 || true
	ok "DKMS module installed: $(modinfo -n btusb)"
}

setup_btusb() {
	if btusb_has_id; then
		ok "btusb already supports 2c7c:0130 - no patch needed"
		return
	fi

	warn "btusb does not know 2c7c:0130 (this kernel is older than v6.13)"

	if [ "$(kver_mm)" = "6.8" ] && [ -f "$HERE/btusb/src-6.8/btusb.c" ]; then
		install_btusb_dkms
	else
		info "kernel $(kver_mm) != 6.8 - rebuilding btusb from the distro kernel source"
		bash "$HERE/scripts/build-btusb-from-source.sh" || die "btusb rebuild failed"
	fi

	modinfo btusb 2>/dev/null | grep -qi 'v2C7Cp0130' \
		&& ok "btusb now advertises 2c7c:0130" \
		|| warn "module installed but the alias is still missing - check depmod output"
}

# ----------------------------------------------------------------- main ------
as_root "$@"

echo "=============================================================="
echo " Qualcomm FastConnect 7800 (WCN7850 / NCM865) - Linux setup"
echo " distro $(distro_id) $(distro_ver)   kernel $(uname -r)"
echo "=============================================================="

check_kernel
install_firmware
setup_btusb

if secboot_enabled; then
	secureboot_advice
fi

print_summary

echo
info "next steps"
echo "   * WiFi  : after a reboot check  dmesg | grep ath12k  and  iw dev"
echo "   * BT    : bluetoothctl list  /  hciconfig hci0 up"
echo "   * if the card is still invisible, run ./verify.sh"

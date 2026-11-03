#!/usr/bin/env bash
# Shared helpers for the FastConnect 7800 (WCN7850 / NCM865) Linux setup.
# Sourced, never executed directly.

# Callers set HERE to the directory holding install.sh/verify.sh before
# sourcing this file; the bundle root is that same directory.
FC_ROOT="${HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m  ERROR: %s\033[0m\n' "$*" >&2; exit 1; }

as_root() {
	if [ "$(id -u)" -ne 0 ]; then
		exec sudo -E bash "$0" "$@"
	fi
}

distro_id() { . /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}"; }
distro_ver() { . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-0}"; }
distro_like() { . /etc/os-release 2>/dev/null; printf '%s' "${ID_LIKE:-}"; }

kver() { uname -r; }
kver_mm() { uname -r | cut -d. -f1,2; }
# true when running kernel >= $1.$2
kernel_at_least() {
	local maj min
	maj=$(uname -r | cut -d. -f1)
	min=$(uname -r | cut -d. -f2)
	[ "$maj" -gt "$1" ] || { [ "$maj" -eq "$1" ] && [ "$min" -ge "$2" ]; }
}

secboot_enabled() {
	[ -d /sys/firmware/efi ] || return 1
	local sb
	sb=$(cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tail -c 1 | od -An -tu1 | tr -d ' ')
	[ "${sb:-0}" = "1" ]
}

# ---------------------------------------------------------------- firmware --
# Copy the bundled blobs into /lib/firmware.  Never overwrites a newer file
# that a distro package already installed.
install_firmware() {
	local src="$FC_ROOT/firmware" f dest changed=0 missing=0

	if [ ! -d "$src" ] || [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
		info "firmware/ is empty - fetching from the linux-firmware tree"
		bash "$FC_ROOT/scripts/fetch-firmware.sh" || die "firmware download failed"
	fi

	info "installing firmware blobs into /lib/firmware"

	while IFS= read -r -d '' f; do
		dest="/lib/firmware/${f#"$src"/}"
		mkdir -p "$(dirname "$dest")"
		if [ -f "$dest" ] && cmp -s "$f" "$dest"; then
			continue
		fi
		if [ -f "$dest" ]; then
			cp -a "$dest" "$dest.fc-backup" 2>/dev/null || true
		fi
		install -m 0644 "$f" "$dest"
		changed=$((changed + 1))
	done < <(find "$src" -type f -print0)

	for f in ath12k/WCN7850/hw2.0/amss.bin \
	         ath12k/WCN7850/hw2.0/m3.bin \
	         ath12k/WCN7850/hw2.0/board-2.bin \
	         qca/rampatch_usb_00190200.bin \
	         qca/nvm_usb_00190200.bin; do
		[ -f "/lib/firmware/$f" ] || { warn "still missing: /lib/firmware/$f"; missing=$((missing + 1)); }
	done

	if [ "$changed" -gt 0 ]; then
		ok "$changed firmware file(s) installed"
	else
		ok "firmware already up to date"
	fi
	[ "$missing" -eq 0 ] || warn "$missing required firmware file(s) missing"
}

# ------------------------------------------------------------------ btusb ----
btusb_has_id() {
	# module alias is the authoritative answer: it is what udev/modprobe use
	modinfo btusb 2>/dev/null | grep -qi 'v2C7Cp0130' && return 0
	grep -qs 'v2C7Cp0130' /lib/modules/"$(uname -r)"/modules.alias && return 0
	return 1
}

sign_file_tool() {
	find /usr/src /usr/lib/linux-kbuild* -name sign-file -type f 2>/dev/null | head -1
}

# Sign $1 with the distro's MOK key when possible; returns 0 if signed/not needed
sign_module() {
	local mod="$1" sf key crt
	sf=$(sign_file_tool)
	key=/var/lib/shim-signed/mok/MOK.priv
	crt=/var/lib/shim-signed/mok/MOK.der
	if [ -z "$sf" ] || [ ! -f "$key" ] || [ ! -f "$crt" ]; then
		return 1
	fi
	"$sf" sha256 "$key" "$crt" "$mod" || return 1
	ok "module signed with $(basename "$key")"
}

secureboot_advice() {
	local mok=/var/lib/shim-signed/mok/MOK.der
	warn "Secure Boot is enabled; the rebuilt btusb module has to be trusted"
	echo "     Two options:"
	echo "       1) enrol the DKMS/MOK key once (survives kernel updates):"
	echo "            sudo mokutil --import $mok        # set a one-time password"
	echo "            sudo reboot   ->  'Enroll MOK' -> Continue -> Yes -> password"
	echo "          then check:  mokutil --test-key $mok"
	echo "       2) or turn Secure Boot off in the firmware/VM settings"
}

# Build the bundled 6.8 source with plain make - no dkms, no network.
# Used when dkms is missing (fresh/offline system) or FC_NO_DKMS=1.
build_btusb_plain() {
	local krel build
	krel=$(uname -r)

	[ -d "/lib/modules/$krel/build" ] || die "kernel headers for $krel are missing (/lib/modules/$krel/build)"
	command -v make  >/dev/null || die "make is missing"
	command -v gcc   >/dev/null || die "gcc is missing (install build-essential)"
	[ -f "$FC_ROOT/btusb/src-6.8/btusb.c" ] || die "bundled btusb source missing"

	build=$(mktemp -d /tmp/btusb-build.XXXXXX)
	cp "$FC_ROOT"/btusb/src-6.8/* "$build"/
	if command -v python3 >/dev/null; then
		python3 "$FC_ROOT/btusb/patch_btusb.py" "$build/btusb.c" >/dev/null
	fi

	info "compiling btusb against /lib/modules/$krel/build"
	make -C "/lib/modules/$krel/build" M="$build" modules 2>&1 | grep -vE '^\s*(CC|LD|MODPOST|BTF)' | tail -8
	[ -f "$build/btusb.ko" ] || die "compilation failed (see output above)"

	mkdir -p "/lib/modules/$krel/updates"
	[ -f "/lib/modules/$krel/updates/btusb.ko" ] && \
		cp -a "/lib/modules/$krel/updates/btusb.ko" "/lib/modules/$krel/updates/btusb.ko.bak.$(date +%s)"
	install -m 0644 "$build/btusb.ko" "/lib/modules/$krel/updates/btusb.ko"
	rm -f "/lib/modules/$krel/updates/btusb.ko.zst"

	sign_module "/lib/modules/$krel/updates/btusb.ko" || warn "module left unsigned (no MOK key)"
	depmod -a "$krel"
	update-initramfs -u -k "$krel" >/dev/null 2>&1 || true
	rm -rf "$build"
	ok "installed $(modinfo -n btusb)"
}

# --------------------------------------------------------------- reporting ---
print_summary() {
	local dev_wifi="absent" dev_bt="absent"
	lspci -nn 2>/dev/null | grep -qi '17cb:1107' && dev_wifi="present"
	lsusb 2>/dev/null | grep -qi '2c7c:0130' && dev_bt="present"

	echo
	echo "-------------------- summary --------------------"
	printf '  kernel          : %s\n' "$(uname -r)"
	printf '  distro          : %s %s\n' "$(distro_id)" "$(distro_ver)"
	printf '  WiFi PCI 17cb:1107 : %s\n' "$dev_wifi"
	printf '  BT   USB 2c7c:0130 : %s\n' "$dev_bt"
	printf '  ath12k module      : %s\n' "$(modinfo -F filename ath12k 2>/dev/null || echo 'missing')"
	if btusb_has_id; then
		printf '  btusb knows 2c7c:0130 : yes\n'
	else
		printf '  btusb knows 2c7c:0130 : NO\n'
	fi
	printf '  ath12k firmware    : %s\n' "$([ -f /lib/firmware/ath12k/WCN7850/hw2.0/amss.bin ] && echo present || echo 'MISSING')"
	printf '  QCA USB BT firmware: %s\n' "$([ -f /lib/firmware/qca/rampatch_usb_00190200.bin ] && echo present || echo 'MISSING')"
	printf '  Secure Boot        : %s\n' "$(secboot_enabled && echo enabled || echo disabled)"
	echo "-------------------------------------------------"
	[ "$dev_wifi" = present ] || warn "no WiFi PCI device visible to this kernel (VM without passthrough? see README)"
	[ "$dev_bt" = present ] || warn "no Bluetooth USB device visible to this kernel (VM without USB attach? see README)"
}

#!/usr/bin/env bash
#
# Rebuild btusb.ko for the *running* kernel from that distro's own kernel
# source, with the Qualcomm WCN785x USB IDs (2c7c:0130/0131/0132) added.
#
#   sudo ./scripts/build-btusb-from-source.sh
#
# This is the fallback for kernels that are not 6.8.x, where the bundled
# btusb source (used by the DKMS path) would not compile against the headers.
# It needs deb-src enabled; the script enables it if it is missing.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HERE/lib.sh"

CACHE=${FC_CACHE:-/var/cache/fastconnect}
KREL=$(uname -r)

as_root "$@"

install_pkgs() {
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null || die "apt-get install failed: $*"
}

info "preparing to rebuild btusb for $KREL"
install_pkgs build-essential python3 dpkg-dev "linux-headers-$KREL"

# ------------------------------------------------------------- deb-src ------
ensure_deb_src() {
	if grep -rhs '^deb-src ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -q .; then
		return
	fi
	warn "no deb-src entries found - enabling them for the configured mirrors"
	local tmp
	tmp=$(mktemp)
	grep -rhs '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null |
		sed -e 's/^deb \[/deb-src [/' -e 's/^deb /deb-src /' |
		grep -v 'launchpadcontent.net' > "$tmp"
	[ -s "$tmp" ] || die "could not derive deb-src lines from /etc/apt/sources.list"
	cp /etc/apt/sources.list "/etc/apt/sources.list.fc-backup.$(date +%s)" 2>/dev/null || true
	install -m 0644 "$tmp" /etc/apt/sources.list.d/fastconnect-src.list
	rm -f "$tmp"
	apt-get update -qq || die "apt-get update failed"
}

ensure_deb_src

# --------------------------------------------------------- source pkg -------
pkg_info() { apt-cache show "linux-image-$KREL" 2>/dev/null; }
SRC_NAME=$(pkg_info | awk '/^Source:/{print $2; exit}')
SRC_VER=$(pkg_info | awk '/^Version:/{print $2; exit}')
[ -n "$SRC_NAME" ] || SRC_NAME=linux

info "source package: $SRC_NAME ${SRC_VER:-(latest)}"
mkdir -p "$CACHE"
cd "$CACHE" || die "cannot enter $CACHE"

if [ -n "${FC_TREE:-}" ] && [ -d "$FC_TREE" ]; then
	info "reusing extracted tree $FC_TREE"
	TREE="$FC_TREE"
else
	if [ -z "$(ls -1 ./*.dsc 2>/dev/null)" ]; then
		if [ -n "$SRC_VER" ]; then
			apt-get source --download-only "$SRC_NAME=$SRC_VER" || \
				apt-get source --download-only "$SRC_NAME" || die "apt-get source failed"
		else
			apt-get source --download-only "$SRC_NAME" || die "apt-get source failed"
		fi
	fi
	find . -maxdepth 1 -name '*.dsc' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2- > .dsc.path
	DSC=$(cat .dsc.path)
	[ -n "$DSC" ] || die "no .dsc in $CACHE"
	info "extracting $(basename "$DSC")"
	dpkg-source -x "$DSC" >/dev/null || die "dpkg-source -x failed"
	TREE=$(find . -maxdepth 1 -type d -name "${SRC_NAME}-*" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
	[ -n "$TREE" ] || die "extracted tree not found"
fi

BT="$TREE/drivers/bluetooth"
[ -f "$BT/btusb.c" ] || die "btusb.c not found under $BT"

# --------------------------------------------------------------- build ------
BUILD="$CACHE/build-$KREL"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cp "$BT/btusb.c" "$BT/btintel.h" "$BT/btbcm.h" "$BT/btrtl.h" "$BT/btmtk.h" "$BUILD"/
python3 "$HERE/btusb/patch_btusb.py" "$BUILD/btusb.c" || die "patch failed"
printf 'obj-m := btusb.o\n' > "$BUILD/Makefile"

info "compiling against /lib/modules/$KREL/build"
make -C "/lib/modules/$KREL/build" M="$BUILD" modules 2>&1 | grep -vE '^\s*(CC|LD|MODPOST|BTF)' | tail -15
[ -f "$BUILD/btusb.ko" ] || die "compilation failed"

# ------------------------------------------------------------- install ------
DEST="/lib/modules/$KREL/updates"
mkdir -p "$DEST"
[ -f "$DEST/btusb.ko" ] && cp -a "$DEST/btusb.ko" "$DEST/btusb.ko.bak.$(date +%s)"
install -m 0644 "$BUILD/btusb.ko" "$DEST/btusb.ko"
[ -f "$DEST/btusb.ko.zst" ] && rm -f "$DEST/btusb.ko.zst"

sign_module "$DEST/btusb.ko" || warn "module left unsigned (no MOK key found)"

depmod -a "$KREL"
update-initramfs -u -k "$KREL" >/dev/null 2>&1 || true

ok "installed $(modinfo -n btusb)"
modinfo btusb | grep -qi 'v2C7Cp0130' && ok "btusb advertises 2c7c:0130" || warn "alias still missing"

echo
echo "  to activate now:   sudo modprobe -r btusb 2>/dev/null; sudo modprobe btusb"
echo "  to roll back:      sudo rm -f $DEST/btusb.ko && sudo depmod -a"

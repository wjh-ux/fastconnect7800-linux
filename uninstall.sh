#!/usr/bin/env bash
#
# Undo everything install.sh / build-btusb-from-source.sh did.
# Firmware stays in /lib/firmware (harmless), the .fc-backup copies win back.
#
#   sudo ./uninstall.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

as_root "$@"

info "removing DKMS package btusb-fastconnect"
if dkms remove btusb-fastconnect/1.0 --all >/dev/null 2>&1; then
	ok "dkms module removed"
else
	warn "dkms package not installed"
fi
rm -rf /usr/src/btusb-fastconnect-1.0

info "removing the hand-built module from /lib/modules"
KREL=$(uname -r)
DEST="/lib/modules/$KREL/updates"
if [ -f "$DEST/btusb.ko" ]; then
	rm -f "$DEST/btusb.ko"
	ok "removed $DEST/btusb.ko"
fi
LATEST_BAK=$(find "$DEST" -maxdepth 1 -name 'btusb.ko.bak.*' -printf '%T@ %p\n' 2>/dev/null |
	sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$LATEST_BAK" ]; then
	cp -a "$LATEST_BAK" "$DEST/btusb.ko"
	ok "restored backup $(basename "$LATEST_BAK")"
fi
depmod -a
update-initramfs -u >/dev/null 2>&1 || true

info "modprobe will now use the stock module again: $(modinfo -n btusb)"

if [ -f /etc/apt/sources.list.d/fastconnect-src.list ]; then
	warn "left /etc/apt/sources.list.d/fastconnect-src.list in place (remove it to drop deb-src)"
fi
warn "firmware blobs stay in /lib/firmware (safe; a linux-firmware update will replace them)"

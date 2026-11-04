#!/usr/bin/env bash
#
# Offline install - for a machine that has no network at all (e.g. booting
# Ubuntu To Go on the laptop before WiFi works).
#
#   sudo ./install-offline.sh
#
# It unpacks the .debs bundled in debs/ (dkms, headers, build tools) and then
# runs install.sh with apt disabled.  Everything else - firmware, btusb
# source, patch - is already inside this directory.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

as_root "$@"

info "offline install from $HERE"

if compgen -G "$HERE/debs/*.deb" >/dev/null 2>&1; then
	info "unpacking bundled packages"
	dpkg -i "$HERE"/debs/*.deb 2>&1 |
		grep -viE 'already installed|already the newest|^Preparing|^Unpacking|^Setting up|^Processing' |
		tail -20 || true
	ok "$(find "$HERE/debs" -maxdepth 1 -name '*.deb' | wc -l) package(s) unpacked"
else
	warn "no debs/ directory - using whatever is already installed"
fi

# prerequisites we cannot conjure offline
command -v gcc >/dev/null || warn "gcc missing - put build-essential_*.deb into debs/"
[ -d "/lib/modules/$(uname -r)/build" ] || \
	warn "kernel headers for $(uname -r) missing - put linux-headers-$(uname -r)*.deb into debs/"

FC_OFFLINE=1 exec bash "$HERE/install.sh" "$@"

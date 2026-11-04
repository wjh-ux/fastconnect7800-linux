#!/usr/bin/env bash
#
# Pre-download the packages install-offline.sh needs into ../debs.
# Run this on a machine of the SAME distro release and kernel as the target,
# while it still has network.
#
#   ./scripts/fetch-debs.sh
#
# On the target (no network):
#   sudo ./install-offline.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/debs"
KREL=$(uname -r)

[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

command -v apt-get >/dev/null || { echo "apt-based distro required" >&2; exit 1; }

PKGS=(dkms build-essential dpkg-dev "linux-headers-$KREL")

# Ubuntu splits the real header payload into a linux-<flavour>-headers-<abi>
# package; grab whichever is installed so the offline box can build too.
while read -r p; do
	[ -n "$p" ] && PKGS+=("$p")
done < <(dpkg-query -W -f='${Package}\n' 'linux-*-headers-*' 2>/dev/null | grep -E '^linux-(hwe-)?[0-9]' || true)

mkdir -p "$DEST"
rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true

echo "downloading: ${PKGS[*]}"
apt-get install --download-only --reinstall -y "${PKGS[@]}" >/dev/null || {
	echo "apt-get download failed" >&2
	exit 1
}

cp -a /var/cache/apt/archives/*.deb "$DEST"/ 2>/dev/null
chmod 0644 "$DEST"/*.deb 2>/dev/null || true

echo
ls -1sh "$DEST"/*.deb
echo
echo "$(find "$DEST" -maxdepth 1 -name '*.deb' | wc -l) package(s), $(du -sh "$DEST" | cut -f1) in $DEST"

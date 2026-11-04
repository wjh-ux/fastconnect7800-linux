#!/usr/bin/env bash
#
# Download the 21 firmware files this card needs into ../firmware and verify
# them against firmware/SHA256SUMS (which is tracked in git).
#
#   ./scripts/fetch-firmware.sh
#
# Files come straight from the linux-firmware tree (Qualcomm proprietary,
# redistributable - see NOTICE).  Two mirrors are tried, because kernel.org
# occasionally answers non-browser clients with a bot challenge.
#
# If upstream linux-firmware has moved on, the pinned hashes will not match and
# this script stops.  That is intentional: it means the blobs changed, so they
# deserve a look before they get installed with root.  To accept the new ones:
#
#   sudo FC_ALLOW_NEW_FW=1 ./scripts/fetch-firmware.sh   # prints the new hashes
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/firmware"
SUMS="$DEST/SHA256SUMS"

MIRRORS=(
	"https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
	"https://raw.githubusercontent.com/torvalds/linux-firmware/main"
)

FILES=(
	ath12k/WCN7850/hw2.0/amss.bin
	ath12k/WCN7850/hw2.0/m3.bin
	ath12k/WCN7850/hw2.0/board-2.bin
	qca/rampatch_usb_00190200.bin
	qca/nvm_usb_00190200.bin
	qca/nvm_usb_00190200_0104.bin
	qca/nvm_usb_00190200_0106.bin
	qca/nvm_usb_00190200_0108.bin
	qca/nvm_usb_00190200_0109.bin
	qca/nvm_usb_00190200_010a.bin
	qca/nvm_usb_00190200_010c.bin
	qca/nvm_usb_00190200_010e.bin
	qca/nvm_usb_00190200_0110.bin
	qca/nvm_usb_00190200_0111.bin
	qca/nvm_usb_00190200_0112.bin
	qca/hmtbtfw20.tlv
	qca/hmtnv20.bin
	qca/hmtnv20.b10f
	qca/hmtnv20.b112
	qca/hmtnv20.b201
	qca/hmtnv20.b202
)

command -v curl     >/dev/null || { echo "curl is required"     >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 1; }

PINNED=0
[ -s "$SUMS" ] && PINNED=1

expected() { # expected <relative path> -> hash or empty
	awk -v f="$1" '$2 == f { print $1; exit }' "$SUMS" 2>/dev/null
}

download_one() {
	local rel="$1" out="$2" m
	for m in "${MIRRORS[@]}"; do
		if curl -fsSL --retry 2 --max-time 90 -o "$out.part" "$m/$rel" 2>/dev/null; then
			# reject HTML bot-check pages: real blobs never start with '<'
			if [ "$(head -c 1 "$out.part")" != "<" ] && [ "$(wc -c <"$out.part")" -gt 900 ]; then
				return 0
			fi
		fi
		rm -f "$out.part"
	done
	return 1
}

echo "fetching firmware into $DEST"
FAILED=0
CHANGED=()

for rel in "${FILES[@]}"; do
	out="$DEST/$rel"
	mkdir -p "$(dirname "$out")" 2>/dev/null

	if ! download_one "$rel" "$out"; then
		printf '  FAIL %-45s (no mirror answered)\n' "$rel"
		FAILED=$((FAILED + 1))
		continue
	fi

	got=$(sha256sum "$out.part" | cut -d' ' -f1)
	want=$(expected "$rel")

	if [ "$PINNED" = 1 ] && [ -n "$want" ] && [ "$got" != "$want" ]; then
		if [ "${FC_ALLOW_NEW_FW:-0}" = "1" ]; then
			printf '  NEW  %-45s %s (not the pinned hash)\n' "$rel" "$got"
			CHANGED+=("$got  $rel")
		else
			printf '  FAIL %-45s hash mismatch - upstream changed it\n' "$rel"
			printf '       pinned: %s\n       got:    %s\n' "$want" "$got"
			rm -f "$out.part"
			FAILED=$((FAILED + 1))
			continue
		fi
	else
		printf '  ok   %-45s %8s bytes\n' "$rel" "$(wc -c <"$out.part")"
	fi

	mv "$out.part" "$out"
done

echo
if [ "${#CHANGED[@]}" -gt 0 ]; then
	echo "new upstream blobs (FC_ALLOW_NEW_FW=1):" >&2
	printf '%s\n' "${CHANGED[@]}" >&2
	echo "review them, then update firmware/SHA256SUMS and commit." >&2
fi

if [ "$FAILED" -eq 0 ] && [ "${#CHANGED[@]}" -eq 0 ]; then
	if [ "$PINNED" = 1 ]; then
		echo "all ${#FILES[@]} files present and matching firmware/SHA256SUMS"
	else
		echo "all ${#FILES[@]} files present (no SHA256SUMS to check against)"
	fi
	exit 0
fi

if [ "$FAILED" -gt 0 ]; then
	echo "$FAILED file(s) failed." >&2
	echo "Alternative: install your distro's firmware package" >&2
	echo "  Ubuntu: sudo apt install linux-firmware      (>= 2024, else too old)" >&2
	echo "  Debian: sudo apt install firmware-atheros" >&2
	exit 1
fi
exit 0

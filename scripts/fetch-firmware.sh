#!/usr/bin/env bash
#
# Download the 21 firmware files this card needs into ../firmware.
# Called automatically by install.sh when firmware/ is empty.
#
#   ./scripts/fetch-firmware.sh
#
# Files come straight from the linux-firmware tree (Qualcomm proprietary,
# redistributable - see NOTICE).  Two mirrors are tried, because kernel.org
# occasionally answers non-browser clients with a bot challenge.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/firmware"

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

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

fetch_one() {
	local rel="$1" out="$DEST/$1" m
	mkdir -p "$(dirname "$out")"
	for m in "${MIRRORS[@]}"; do
		if curl -fsSL --retry 2 --max-time 90 -o "$out.part" "$m/$rel" 2>/dev/null; then
			# reject HTML bot-check pages: real blobs never start with '<'
			if [ "$(head -c 1 "$out.part")" != "<" ] && [ "$(wc -c <"$out.part")" -gt 900 ]; then
				mv "$out.part" "$out"
				printf '  ok   %-45s %8s bytes\n' "$rel" "$(wc -c <"$out")"
				return 0
			fi
		fi
		rm -f "$out.part"
	done
	printf '  FAIL %s\n' "$rel"
	return 1
}

echo "fetching firmware into $DEST"
FAILED=0
for f in "${FILES[@]}"; do
	fetch_one "$f" || FAILED=$((FAILED + 1))
done

echo
if [ "$FAILED" -eq 0 ]; then
	echo "all ${#FILES[@]} files present"
	exit 0
fi
echo "$FAILED file(s) failed." >&2
echo "Alternative: install your distro's firmware package" >&2
echo "  Ubuntu: sudo apt install linux-firmware      (>= 2024, else too old)" >&2
echo "  Debian: sudo apt install firmware-atheros" >&2
exit 1

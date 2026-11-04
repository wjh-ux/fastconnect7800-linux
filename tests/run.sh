#!/usr/bin/env bash
#
# Static self-check - no root, no hardware, no network.
# Runs in CI and can be run by anyone before sending a patch:
#
#   bash tests/run.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

FAIL=0
pass() { printf '  \033[1;32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "1) shell syntax"
for f in install.sh install-offline.sh verify.sh uninstall.sh lib.sh \
         scripts/*.sh tests/run.sh; do
	[ -f "$f" ] || continue
	if bash -n "$f" 2>/dev/null; then pass "$f"; else fail "$f (bash -n)"; fi
done

echo "2) no CRLF anywhere (scripts would break on Linux)"
if grep -rIl $'\r' --include='*.sh' --include='*.py' --include='*.c' --include='*.h' . 2>/dev/null | grep -q .; then
	fail "CRLF found in: $(grep -rIl $'\r' --include='*.sh' --include='*.py' --include='*.c' . | tr '\n' ' ')"
else
	pass "all text files are LF"
fi

echo "3) scripts are executable"
for f in install.sh install-offline.sh verify.sh uninstall.sh scripts/*.sh; do
	if [ -x "$f" ]; then pass "$f"; else fail "$f is not +x"; fi
done

echo "4) btusb source carries exactly the three WCN785x IDs"
n=$(grep -c 'USB_DEVICE(0x2c7c, 0x01' btusb/src-6.8/btusb.c 2>/dev/null || echo 0)
if [ "$n" -eq 3 ]; then pass "3 IDs present"; else fail "expected 3 USB IDs, found $n"; fi

echo "5) patch script is idempotent"
# note: `command -v python3` alone is not enough - on Windows the Store stub
# answers but does not run, so prove it executes
if command -v python3 >/dev/null 2>&1 && python3 -c 'pass' >/dev/null 2>&1; then
	tmp=$(mktemp)
	if grep -q '0x2c7c, 0x0130' btusb/src-6.8/btusb.c; then
		cp btusb/src-6.8/btusb.c "$tmp"
		if python3 btusb/patch_btusb.py "$tmp" | grep -q 'already patched'; then
			pass "second run is a no-op"
		else
			fail "patch_btusb.py re-applied itself (not idempotent)"
		fi
		rm -f "$tmp"
	else
		fail "btusb.c has no patch applied - cannot test idempotency"
	fi
else
	echo "  skip python3 not available"
fi

echo "6) required files exist"
for f in LICENSE NOTICE README.md README.en.md COMPATIBILITY.md docs/EXPECTED.md \
         install.sh lib.sh btusb/src-6.8/btusb.c btusb/src-6.8/Makefile \
         btusb/patch_btusb.py scripts/build-btusb-from-source.sh \
         scripts/fetch-firmware.sh scripts/fetch-debs.sh scripts/report-machine.sh firmware/SHA256SUMS; do
	if [ -s "$f" ]; then pass "$f"; else fail "$f missing or empty"; fi
done

echo "7) firmware checksum manifest covers the 21 blobs"
sums=$(grep -c '^[0-9a-f]\{64\}  ' firmware/SHA256SUMS 2>/dev/null || echo 0)
if [ "$sums" -eq 21 ]; then pass "21 pinned hashes"; else fail "expected 21 hashes, found $sums"; fi
if grep -q 'ath12k/WCN7850/hw2.0/amss.bin' firmware/SHA256SUMS &&
   grep -q 'qca/rampatch_usb_00190200.bin' firmware/SHA256SUMS; then
	pass "WiFi and Bluetooth blobs are pinned"
else
	fail "manifest is missing the key blobs"
fi

echo
if [ "$FAIL" -eq 0 ]; then
	echo "all checks passed"
	exit 0
fi
echo "$FAIL check(s) failed" >&2
exit 1

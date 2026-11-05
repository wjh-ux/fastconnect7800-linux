#!/usr/bin/env bash
#
# Exercise openwrt/setup-ap.sh without OpenWrt: stub out uci/opkg/wifi/iw/lsmod
# and check the script walks the expected path and emits the expected uci calls.
#
#   bash tests/openwrt-stub-test.sh
#
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STAGE="$TMP/pkg"; mkdir -p "$STAGE"
cp "$HERE/openwrt/setup-ap.sh" "$STAGE/setup-ap.sh"
for n in kmod-ath12k kmod-ath ath12k-firmware-wcn7850; do : > "$STAGE/${n}_test.ipk"; done
SCRIPT="$STAGE/setup-ap.sh"
mkdir -p "$TMP/sys/class/ieee80211/phy0"
export FC_SYSFS="$TMP/sys"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"; mkdir -p "$BIN"
LOG="$TMP/calls.log"; : > "$LOG"
state="$TMP/state"; mkdir -p "$state"

# --- stubs -------------------------------------------------------------
cat > "$BIN/_stub" <<'EOF'
#!/bin/sh
name=$(basename "$0")
echo "$name $*" >> "$CALLS"
EOF
chmod +x "$BIN/_stub"
for c in opkg modprobe sleep; do cp "$BIN/_stub" "$BIN/$c"; done

cat > "$BIN/uci" <<'EOF'
#!/bin/sh
echo "uci $*" >> "$CALLS"
# -q get wireless.radio0 -> 0 once "set" happened
case "$*" in
  "-q get wireless.radio0"*) [ -f "$STATE/radio0" ] && exit 0 || exit 1 ;;
  "set wireless.radio0="*) : > "$STATE/radio0" ;;
  "commit"*) : ;;
  "-q delete"*) : ;;
  "") : ;;
esac
exit 0
EOF
chmod +x "$BIN/uci"

cat > "$BIN/wifi" <<'EOF'
#!/bin/sh
echo "wifi $*" >> "$CALLS"
[ "$1" = "config" ] && : > "$STATE/radio0"
exit 0
EOF
chmod +x "$BIN/wifi"

cat > "$BIN/lsmod" <<'EOF'
#!/bin/sh
echo "lsmod $*" >> "$CALLS"
[ -f "$STATE/loaded" ] && echo "ath12k 200704 0"
exit 0
EOF
chmod +x "$BIN/lsmod"

# opkg install marks the module as loaded
cat > "$BIN/opkg" <<'EOF'
#!/bin/sh
echo "opkg $*" >> "$CALLS"
: > "$STATE/loaded"
exit 0
EOF
chmod +x "$BIN/opkg"

cat > "$BIN/iw" <<'EOF'
#!/bin/sh
echo "iw $*" >> "$CALLS"
[ "$1" = "dev" ] && printf 'phy#0\n\tInterface phy0-ap0\n\t\ttype AP\n'
exit 0
EOF
chmod +x "$BIN/iw"

export PATH="$BIN:$PATH"
export CALLS="$LOG" STATE="$state" FC_FAKE_ROOT=1

fail=0
check() { # check <grep-pattern> <label>
	if grep -q -- "$1" "$LOG"; then printf '  ok    %s\n' "$2"; else printf '  FAIL  %s (missing: %s)\n' "$2" "$1"; fail=1; fi
}

echo "1) 默认参数（2g / ch6）"
: > "$LOG"; rm -f "$state"/* 
PATH="$BIN:$PATH" CALLS="$LOG" STATE="$state" sh "$SCRIPT" >"$TMP/out1" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  ok    exit=0"; else echo "  FAIL  exit=$rc"; sed 's/^/        /' "$TMP/out1"; fail=1; fi
check "opkg install .*kmod-ath12k" "调用 opkg install"
check "uci set wireless.radio0.band=2g" "band=2g"
check "uci set wireless.radio0.htmode=EHT20" "htmode=EHT20"
check "uci set wireless.ap0.ssid=FastConnect-AP" "默认 SSID"
check "uci commit wireless" "commit"
check "wifi reload" "reload"

echo "2) 自定义参数（5g / ch36 / 自定义 SSID）"
: > "$LOG"; rm -f "$state"/*
PATH="$BIN:$PATH" CALLS="$LOG" STATE="$state" sh "$SCRIPT" "MyLab" "Secret12345" 5g 36 >"$TMP/out2" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  ok    exit=0"; else echo "  FAIL  exit=$rc"; fail=1; fi
check "uci set wireless.radio0.band=5g" "band=5g"
check "uci set wireless.radio0.channel=36" "channel=36"
check "uci set wireless.radio0.htmode=EHT80" "htmode=EHT80"
check "uci set wireless.ap0.ssid=MyLab" "自定义 SSID"

echo "3) 模块已加载时不再装包"
: > "$LOG"; : > "$state/loaded"
PATH="$BIN:$PATH" CALLS="$LOG" STATE="$state" sh "$SCRIPT" >/dev/null 2>&1
if grep -q "opkg" "$LOG"; then echo "  FAIL  仍然调用了 opkg"; fail=1; else echo "  ok    跳过 opkg"; fi

echo "4) 非法 band 被拒绝"
: > "$LOG"
PATH="$BIN:$PATH" CALLS="$LOG" STATE="$state" sh "$SCRIPT" a b 3g 1 >/dev/null 2>&1
if [ $? -ne 0 ]; then echo "  ok    非 0 退出"; else echo "  FAIL  应当拒绝 3g"; fail=1; fi

echo
[ "$fail" -eq 0 ] && echo "all stub checks passed" || echo "some checks failed"
exit $fail

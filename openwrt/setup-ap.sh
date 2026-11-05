#!/bin/sh
#
# setup-ap.sh - 在 OpenWrt 24.10 x86/64 上把这台机器的 WiFi 卡配成 AP
#
#   sh /boot/setup-ap.sh                       # 默认 SSID/密码/2.4G ch6
#   sh /boot/setup-ap.sh MySSID MyPass 5g 36   # 自定义
#
# 参数： [ssid] [passphrase] [band: 2g|5g|6g] [channel]
# 环境： COUNTRY=CN（默认）、NO_INSTALL=1（跳过 ipk 安装）
#
# 幂等：重复执行只会改配置并 reload，不会重复装包。
#
set -u

SSID=${1:-FastConnect-AP}
KEY=${2:-ChangeMe-2026}
BAND=${3:-2g}
CHANNEL=${4:-6}
COUNTRY=${COUNTRY:-CN}
SYSFS=${FC_SYSFS:-/sys}      # 只为单元测试可替换

die() { echo "!! $*" >&2; exit 1; }
say() { echo "==> $*"; }

case "$BAND" in
	2g) HTMODE=EHT20 ;;
	5g) HTMODE=EHT80 ;;
	6g) HTMODE=EHT160 ;;
	*) die "band 只能是 2g / 5g / 6g" ;;
esac

{ [ "${FC_FAKE_ROOT:-0}" = "1" ] || [ "$(id -u)" = 0 ]; } || die "请用 root 运行"

# ---------------------------------------------------------------- 1. 装包 --
find_pkgdir() {
	for d in /boot/ipk /mnt/esp/ipk /ipk "$(dirname "$0")"; do
		[ -d "$d" ] && ls "$d"/*.ipk >/dev/null 2>&1 && { echo "$d"; return 0; }
	done
	# EFI 分区可能没自动挂载
	mkdir -p /mnt/esp 2>/dev/null
	mount -t vfat /dev/sda1 /mnt/esp 2>/dev/null
	[ -d /mnt/esp/ipk ] && { echo /mnt/esp/ipk; return 0; }
	return 1
}

if [ "${NO_INSTALL:-0}" != "1" ] && ! lsmod 2>/dev/null | grep -q '^ath12k'; then
	PKGDIR=$(find_pkgdir) || die "找不到 .ipk（应在 /boot/ipk）"
	say "从 $PKGDIR 安装 ath12k"
	opkg install "$PKGDIR"/*.ipk >/dev/null 2>&1 || die "opkg install 失败，手动跑一次看报错"
fi

modprobe ath12k 2>/dev/null
if ! lsmod 2>/dev/null | grep -q '^ath12k'; then
	die "ath12k 没加载：dmesg | grep -i ath12k 看看"
fi

set -- "$SYSFS"/class/ieee80211/phy*
[ -e "$1" ] || die "没有无线 phy：卡没认到，检查 lspci -nn | grep 17cb"
say "ath12k 已加载，phy: $(printf '%s ' "$@" | sed 's#.*/##')"

# --------------------------------------------------------------- 2. radio --
if ! uci -q get wireless.radio0 >/dev/null 2>&1; then
	say "生成默认无线配置（wifi config）"
	wifi config >/dev/null 2>&1
	sleep 1
fi
uci -q get wireless.radio0 >/dev/null 2>&1 || die "没有 wireless.radio0，wifi config 没成功"

# ------------------------------------------------------------ 3. AP 配置 ---
say "ssid=$SSID  band=$BAND  channel=$CHANNEL  htmode=$HTMODE  country=$COUNTRY"

uci set wireless.radio0.disabled='0'
uci set wireless.radio0.band="$BAND"
uci set wireless.radio0.channel="$CHANNEL"
uci set wireless.radio0.htmode="$HTMODE"
uci set wireless.radio0.country="$COUNTRY"

# wifi config 会建一个 default_radio0（sta 或 disabled），删掉避免抢 radio
uci -q delete wireless.default_radio0 >/dev/null 2>&1

uci set wireless.ap0=wifi-iface
uci set wireless.ap0.device='radio0'
uci set wireless.ap0.mode='ap'
uci set wireless.ap0.network='lan'
uci set wireless.ap0.ssid="$SSID"
uci set wireless.ap0.encryption='sae'
uci set wireless.ap0.key="$KEY"
uci set wireless.ap0.isolate='0'

uci commit wireless || die "uci commit 失败"
say "配置已提交，reload"
wifi reload >/dev/null 2>&1
sleep 3

# ------------------------------------------------------------- 4. 结果 ----
echo
if iw dev 2>/dev/null | grep -q 'ap'; then
	echo "✅ AP 已起来："
	iw dev | sed 's/^/   /'
	echo
	echo "   手机连 SSID: $SSID    密码: $KEY"
	echo "   管理页: http://192.168.1.1"
	echo
	echo "   没连上就看日志： logread -e hostapd | tail -30"
else
	echo "❌ 没看到 AP 接口，先看这两条："
	echo "   logread -e hostapd | tail -30"
	echo "   dmesg | grep -i ath12k | tail -20"
	echo
	echo "   band=$BAND channel=$CHANNEL 不被 regdb 允许时也会起不来，"
	echo "   先退回 2.4G： sh $0 \"$SSID\" \"$KEY\" 2g 6"
	exit 1
fi

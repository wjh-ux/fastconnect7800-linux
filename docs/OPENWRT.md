# OpenWrt / iStoreOS 适配

这块卡在路由器系统上能不能用，**取决于内核版本，不是发行版名字**。两张表先看结论，
再往下看怎么做。

## 1. 支持矩阵（按内核）

| 系统 | 内核 | WiFi（ath12k） | 蓝牙（btusb `2c7c:0130`） |
|---|---|---|---|
| OpenWrt 23.05 | 5.15 | ❌ 根本没有 ath12k | — |
| **OpenWrt 24.10** | **6.6** | ✅ `kmod-ath12k` + `ath12k-firmware-wcn7850`，6.6 的 ath12k 已认 PCI `0x1107` | ❌ 需打补丁（ID 到 v6.13 才进主线） |
| OpenWrt snapshot（25.x） | 6.18 | ✅（含 `ath12k_wifi7` 子模块） | ✅ 原生支持，无需补丁 |
| iStoreOS | 视版本（多为 5.x～6.6） | 先 `opkg list \| grep -i ath12k` 确认；没有就只能自编译 | 同上，按内核判断 |

为什么会有这个分界：

- `ath12k` 对 WCN7850 的支持在 **6.3** 进主线（`drivers/net/wireless/ath/ath12k/pci.c`
  里的 `#define WCN7850_DEVICE_ID 0x1107`）；
- `btusb` 对 `2c7c:0130` 的支持在 **6.13** 才进主线。

所以 6.6 的 OpenWrt 是「**WiFi 可以、蓝牙不行**」，而 snapshot（6.18）两个都行。

> 上面「6.6 认 0x1107」「23.05 没有 ath12k」「24.10 内核 6.6 / snapshot 6.18」
> 都是从 OpenWrt 与 Linux 源码里核对过的，不是猜的。

## 2. 装 WiFi（OpenWrt 24.10）

```sh
opkg update
opkg install kmod-ath12k ath12k-firmware-wcn7850 iw
```

或者直接跑本仓库的脚本（做的事一样，外加检查与 UCI 模板）：

```sh
chmod +x scripts/install-openwrt.sh
./scripts/install-openwrt.sh
```

固件落位和 Ubuntu 一样：

```
/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin
/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin
/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
```

验证：

```sh
lspci -nn | grep 17cb        # 17cb:1107
lsmod | grep ath12k
iw dev                       # phy0
iw phy | grep -i band        # Band 1 / 2 / 4
```

## 3. 配成 AP（UCI）

> 已经有一块写好的 OpenWrt U 盘？那份逐步操作（含离线装 ath12k）在
> [FIRST-BOOT-OPENWRT.md](FIRST-BOOT-OPENWRT.md)，下面这段是同样的配置思路。

`/etc/config/wireless`，2.4 GHz 起步最稳，跑通再换 5 / 6 GHz：

```
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'pci0000:00/0000:00:03.0'    # 用 iw dev 里的 phy 路径
	option band '2g'
	option channel '6'
	option htmode 'EHT20'
	option country 'CN'
	option cell_density '0'

config wifi-iface 'default_radio0'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'MyWiFi7'
	option encryption 'sae'
	option key 'your-password'
```

5 GHz：`option band '5g'` + `option channel '36'`（或 `auto`）。
6 GHz：`option band '6g'` + `option channel '37'`，**必须**设 `country`，而且要
`iw reg get` 里允许；hostapd 没有 6 GHz 支持时这条配置会被拒（看 `logread -e hostapd`）。

改完 `wifi reload`。

## 4. 蓝牙

**先说结论：x86/64 的 OpenWrt 24.10 根本装不了 `kmod-btusb`。** 它的 `DEPENDS` 里带
`+kmod-btmtk`，而 `kmod-btmtk` 没有为 x86 目标构建（kmods 索引里查不到），所以包管理器
直接判依赖不满足。也就是说 Bluetooth 在这里不但要打 ID 补丁，还得自编译内核模块 ——
比 WiFi 那条路难得多。

这带来两个选择：

1. **不折腾蓝牙**：WiFi 用它，蓝牙用 USB 蓝牙棒（路由器上最简单）；
2. **自编译**：`make menuconfig` 里打开 `kmod-btusb` 并把 `kmod-btmtk` 一起选上，
   再打 `openwrt/patches/` 里的 ID 补丁（6.6 缺 ID），固件自己放进 `/lib/firmware/qca/`。

真要在支持的平台上试，命令是：

```sh
opkg install kmod-btusb bluez-daemon bluez-utils
```

OpenWrt 不打包的那两个固件，从仓库 `firmware/qca/` 拷到 `/lib/firmware/qca/` 即可
（`install-openwrt.sh --with-bt` 会在同一目录时替你拷）。

实话实说：路由器上跑蓝牙的用途有限（BLE 传感器、串口/网络桥），bluez 在 OpenWrt 上
不是桌面级体验，配对/音频基本别指望。

## 5. 自己编译镜像

```sh
make menuconfig
#   Kernel modules → Wireless Drivers → kmod-ath12k
#   Firmware → ath12k-firmware-wcn7850
#   Kernel modules → Bluetooth → kmod-btusb        (需要蓝牙时)
```

如果目标内核 < 6.6，先把内核升到 6.6+ —— 否则 ath12k 连编译选项都没有。

**iStoreOS**：它是 OpenWrt 的派生版，`opkg` 命令与上面一致，但它的 feed 与内核分支
跟上游不完全同步（老版本停在 5.x）。判断顺序：

```sh
opkg update; opkg list | grep -i ath12k     # 有包 → 按第 2 节装
uname -r                                    # < 6.6 → 别折腾了，换上游 OpenWrt
```

真要在 iStoreOS 上跑这张卡，最省事的是：用上游 OpenWrt 24.10 出镜像，iStoreOS 的
LuCI 主题/插件另行安装，而不是把 ath12k 移植回老内核。

## 6. 已知限制

- **MLO（WiFi 7 多链路）**：6.6 的 ath12k 还没有 MLO 实现，24.10 上只有单链路 EHT；
  要 MLO 得用 snapshot 级别的新内核。以 `iw phy` 实际输出为准。
- **6 GHz AP**：依赖 hostapd 的 6 GHz 支持 + regdb + `country`，三者缺一就起不来。
- **DFS / 160 MHz**：视国家码与信道，别一上来就用高带宽。
- **蓝牙**：24.10 必须自编译内核补丁；不支持热插拔折腾，重启后靠 kmod 自动加载。
- 这张卡是 **PCIe** 设备，接在软路由上要确认主板 M.2 槽是 PCIe 而不是仅 SATA。

## 7. 排障

| 症状 | 原因 | 处理 |
|---|---|---|
| `opkg install kmod-ath12k` 报找不到包 | feed 里没有（老分支 / iStoreOS 精简） | 换 24.10+ 或自编译 |
| `lspci` 有 `17cb:1107`，`iw dev` 没有 phy | 固件没装或 ath12k 没加载 | `dmesg \| grep ath12k`，装 `ath12k-firmware-wcn7850` |
| `dmesg` 报 `failed to load firmware` | 固件路径不对 | 确认 `/lib/firmware/ath12k/WCN7850/hw2.0/` 三个文件 |
| hostapd 起不来、日志说 band 不支持 | hostapd 不支持 6 GHz 或 country 没设 | 先 2.4/5 GHz，补 `country` |
| `modinfo btusb` 没有 `2C7C` | 内核 < 6.13 | 打补丁重编，或换 snapshot |
| 蓝牙 `hci0` 不出现 | 固件没放 / USB 未识别 | `lsusb \| grep 2c7c`、`dmesg \| grep btusb` |

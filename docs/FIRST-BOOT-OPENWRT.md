# OpenWrt 首启：把这块卡配成 AP

盘里是 **OpenWrt 24.10.0 x86/64（内核 6.6.73）**，WiFi 驱动（ath12k）和固件没有预装，
但已经放在 EFI 分区的 `/boot/ipk/` 里了。下面按顺序敲，全程只要键盘。

---

## 0. 开机前：关掉 Secure Boot

OpenWrt 的 EFI 引导程序没有微软签名，Secure Boot 开着会直接拒绝启动。

```
Dell 开机按 F2 → Security → Secure Boot → Disabled → Apply → 重启
```

启动菜单：**F12** → 选 `UEFI: thinkplus TU180Pro`（别选 Legacy/BIOS 那一项）。

---

## 1. 首次进入

登录名 `root`，**密码为空**，直接回车。第一件事设密码：

```sh
passwd
```

看下网卡现状（此时只有 `lo`，可能还有个 `eth0`）：

```sh
ip -br link
```

---

## 2. 装 ath12k（离线）

```sh
ls /boot/ipk
```

应该看到 6 个 `.ipk`。看到就直接装：

```sh
opkg install /boot/ipk/*.ipk
```

如果 `/boot` 是空的（EFI 分区没自动挂载），手动挂：

```sh
mkdir -p /mnt/esp
mount -t vfat /dev/sda1 /mnt/esp
opkg install /mnt/esp/ipk/*.ipk
```

装完确认：

```sh
lsmod | grep ath12k          # 6.6 只有 ath12k，没有 ath12k_wifi7
iw phy                       # 这时还没配无线，但应该能列出 phy0
ls /lib/firmware/ath12k/WCN7850/hw2.0/
dmesg | grep -i ath12k | tail -20
```

`dmesg` 里出现 `firmware` 加载成功、`wiphy` 注册，就说明卡认到了。

---

## 3. 生成 radio 配置

```sh
wifi config
uci show wireless
```

`wifi config` 会探测 phy 并写出 `radio0`（默认 `disabled='1'`）。

---

## 4. 改成 AP（先 2.4 GHz，最稳）

```sh
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.band='2g'
uci set wireless.radio0.channel='6'
uci set wireless.radio0.htmode='EHT20'
uci set wireless.radio0.country='CN'
uci set wireless.radio0.cell_density='0'

uci delete wireless.default_radio0 2>/dev/null
uci set wireless.wifinet0=wifi-iface
uci set wireless.wifinet0.device='radio0'
uci set wireless.wifinet0.mode='ap'
uci set wireless.wifinet0.network='lan'
uci set wireless.wifinet0.ssid='FastConnect-AP'
uci set wireless.wifinet0.encryption='sae'
uci set wireless.wifinet0.key='ChangeMe-2026'

uci commit wireless
wifi reload
```

> `encryption='sae'` 是 WPA3。老设备连不上就换 `psk2`（WPA2），别两个都试。

---

## 5. 验证

```sh
iw dev                     # 出现 phy0-ap0
iw dev phy0-ap0 info       # ssid / channel / type AP
logread -e hostapd | tail -20
```

手机搜 `FastConnect-AP` 能连上、能拿到 `192.168.1.x` 地址 = 成了。
这台笔记本没有网口，所以管理页面就在 **http://192.168.1.1**（从手机连上 AP 后访问）。

---

## 6. 换 5 GHz / 6 GHz

5 GHz：

```sh
uci set wireless.radio0.band='5g'
uci set wireless.radio0.channel='36'
uci set wireless.radio0.htmode='EHT80'
uci commit wireless && wifi reload
```

6 GHz（要 hostapd 支持 + regdb 允许 + `country` 设对，三者缺一起不来）：

```sh
uci set wireless.radio0.band='6g'
uci set wireless.radio0.channel='37'
uci set wireless.radio0.htmode='EHT160'
uci commit wireless && wifi reload
iw reg get          # 确认 6 GHz 频段没被 regdb 禁掉
```

`htmode` 支持 `EHT20/40/80/160/320`（已在 24.10 的 `mac80211.sh` 里核对过）；
6 GHz 的 `band` 值就是 `6g`。

---

## 7. 顺便当 STA 上网（可选）

如果想让这台机器连你家路由、临时有网（能装别的包）：

```sh
uci set wireless.sta0=wifi-iface
uci set wireless.sta0.device='radio0'
uci set wireless.sta0.mode='sta'
uci set wireless.sta0.network='wan'
uci set wireless.sta0.ssid='你家WiFi名'
uci set wireless.sta0.encryption='psk2'
uci set wireless.sta0.key='你家WiFi密码'
uci commit wireless && wifi reload
```

`ifstatus wan | grep -E 'up|address'` 看到地址就成了。

---

## 8. 出问题先看这几条

| 现象 | 原因 | 处理 |
|---|---|---|
| 开机直接进 Windows / 没有 U 盘选项 | Secure Boot 没关，或选了 Legacy | F2 关 SB，F12 选 UEFI 那项 |
| `opkg install` 报 `Unknown package` | 路径不对 / 没挂载 | `ls /boot/ipk`，或手动挂 `/dev/sda1` |
| `iw dev` 没有 phy | ath12k 没装或固件没到位 | `lsmod \| grep ath12k`；`ls /lib/firmware/ath12k/WCN7850/hw2.0/` |
| `dmesg` 报 `failed to load firmware` | 固件包没装上 | 重装 `ath12k-firmware-wcn7850*.ipk` |
| AP 起不来，`logread` 说 channel/band | 信道不在 regdb 允许范围 | 先 2.4G channel 6，`country` 设 `CN` |
| 手机能连但没 IP | `network='lan'` 没对上 / dnsmasq 没跑 | `uci show network`，`/etc/init.d/dnsmasq restart` |
| 蓝牙 | **x86/64 的 24.10 根本没有 kmod-btusb** | 别试了，插 USB 蓝牙棒或自编译镜像 |

---

## 备注

- 这张卡是 **PCIe** 的，MSI/中断都正常时 `dmesg` 里能看到 `ath12k_pci 0000:xx:00.0`。
- 6 GHz 与 MLO：24.10 的 ath12k 没有 MLO 实现，只有单链路 EHT；别期待 WiFi 7 多链路。
- 装好后如果哪天要恢复 Ubuntu To Go，把另一块 Coolfish 盘插回去即可，两个系统互不影响。

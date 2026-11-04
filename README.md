# FastConnect 7800 (WCN7850 / NCM865) on Ubuntu & Debian

[![ci](https://github.com/wjh-ux/fastconnect7800-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/wjh-ux/fastconnect7800-linux/actions/workflows/ci.yml)
[![license: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)
![platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-informational)
![kernel](https://img.shields.io/badge/kernel-%E2%89%A5%206.8%20%2F%20BT%20%E2%89%A5%206.13-lightgrey)

WiFi 7 + Bluetooth driver setup for the **Qualcomm FastConnect 7800** — the M.2 module
that Windows calls *"Qualcomm FastConnect 7800 Wi-Fi 7 High Band Simultaneous (HBS)
Network Adapter"* (PCI `17cb:1107`, module **NCM865**, USB BT `2c7c:0130`).

**TL;DR** — WiFi needs no driver at all: in-tree `ath12k` + the `ath12k/WCN7850/hw2.0`
firmware on a kernel ≥ 6.8. Bluetooth is the annoying half: `btusb` only learned the USB ID
`2c7c:0130` in **v6.13**, so older kernels (Ubuntu 22.04/24.04 = 6.8, Debian 12 = 6.1/6.12)
silently treat it as a generic USB dongle, skip the QCA firmware download and die with
`hci0: Opcode 0x0c03 failed: -110`. This repo ships the missing ID as a DKMS module plus the
firmware blobs.

> Verified on Ubuntu 22.04.5 / 6.8.0-138 on real hardware: WiFi connects to an ASUS RT-BE88U,
> a Bluetooth mouse and a Bluetooth headset both connect and work.

---

## 1. 硬件身份（先确认识别没错）

| 功能 | 总线 / ID | 驱动 | 模块 | 状态 |
|------|-----------|------|------|------|
| WiFi 7 | PCI `17cb:1107`（子系统随模块而变，如 `80001EAC`） | `ath12k` | `ath12k` | 主线支持，装固件即可 |
| 蓝牙 | USB `2c7c:0130`（Quectel NCM865） | `btusb` | `btusb` | 内核 ≥ 6.13 原生支持，更老的要补 ID |

需要的固件（文件名由驱动写死，不能改）：

```
/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin      # WiFi
/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin
/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
/lib/firmware/qca/rampatch_usb_00190200.bin      # 蓝牙（名字来自 ROM 版本 0x00190200）
/lib/firmware/qca/nvm_usb_00190200.bin
```

## 2. 快速开始

```bash
git clone https://github.com/wjh-ux/fastconnect7800-linux.git
cd fastconnect7800-linux
sudo ./install.sh          # 需要联网：缺固件时自动下载，缺 dkms/头文件时自动装
```

断电/无网环境（例如 Ubuntu To Go 刚插到笔记本、WiFi 还没起来）：

```bash
# 先在能上网的同版本机器上准备好离线内容
./scripts/fetch-firmware.sh
sudo ./scripts/fetch-debs.sh

# 整包拷到目标机，然后
sudo ./install-offline.sh
```

不想装脚本、只想拿现成的离线包：[Releases](https://github.com/wjh-ux/fastconnect7800-linux/releases)
里有带固件与 deb 的完整 tar.gz。下载后先核对校验和：

```bash
sha256sum -c SHA256SUMS        # 和 tar.gz 放在同一目录
```

## 2.1 前提

- Ubuntu 22.04 / 24.04（Debian 12 需先上 backports 6.12，脚本会处理）—— 其它版本没测过
- 内核 ≥ 6.8（`ath12k` 支持 WCN7850）
- 能 `sudo`，能写 `/lib/firmware` 与 `/lib/modules`
- 装脚本的机器 = 这块卡所在的机器（虚拟机里没有 PCIe 直通，装了也用不上）


## 3. `install.sh` 做了什么

1. **固件** — 把 `firmware/` 里的文件装进 `/lib/firmware`（相同则跳过；被覆盖的留
   `.fc-backup`）。`firmware/` 为空时先跑 `scripts/fetch-firmware.sh`。
2. **内核** — < 6.8 时：Ubuntu 装 `linux-generic-hwe-XX.04`，Debian 加
   `bookworm-backports` 装 6.12，然后让你重启再跑。
3. **btusb** — 顺序判断：
   - 内核已经认识 `2c7c:0130`（≥ 6.13）→ 什么都不做；
   - 6.8.x 且有 dkms → DKMS 模块，`AUTOINSTALL=yes`，换内核自动重编；
   - 6.8.x 没有 dkms（离线/精简系统）→ 一次性 `make`，装到
     `/lib/modules/$(uname -r)/updates/`；
   - 其它内核版本 → `scripts/build-btusb-from-source.sh`：`apt-get source` 取**本机
     这个内核版本**的源码，打同一个补丁，只编 `btusb.ko`。

两条编译路径都会用发行版 MOK 自动签名。

## 4. Secure Boot（唯一必须人工的一步）

自编模块会被拒绝加载：

```
Loading of unsigned module is rejected
Loading of module with unavailable key is rejected
```

DKMS 会用 `/var/lib/shim-signed/mok/MOK.{priv,der}` 签名，但这把 MOK 必须先在固件里注册：

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der   # 设一次性密码
sudo reboot
# 开机屏幕上（不是 SSH）MokManager：Enroll MOK → Continue → Yes → 输密码 → Reboot
mokutil --test-key /var/lib/shim-signed/mok/MOK.der      # ... is already enrolled
```

或者直接在 BIOS 里关掉 Secure Boot。注意 MOK 列表存在**主板 NVRAM**里，不跟硬盘走。

## 5. 验证

```bash
./verify.sh
```

看前两段就够：

```
1) hardware visible to this kernel
0000:03:00.0 Network controller [0280]: Qualcomm ... [17cb:1107]
Bus 003 Device 005: ID 2c7c:0130 Quectel ...

2) drivers
  ath12k : /lib/modules/6.8.0-138-generic/kernel/drivers/net/wireless/ath/ath12k/ath12k.ko
  btusb  : /lib/modules/6.8.0-138-generic/updates/dkms/btusb.ko
  OK btusb advertises 2c7c:0130
```

再看实际功能：

```bash
iw dev                      # wlan0
bluetoothctl list           # hci0
```

## 6. 已知限制

- **6 GHz / WiFi 7 (EHT/MLO)**：`ath12k` 可用，6 GHz 需要 `wireless-regdb` 与国家码
  （`sudo iw reg set CN`），MLO 在部分内核仍不稳；2.4/5 GHz 最稳。
- **蓝牙**：本机（NCM865）鼠标/耳机实测正常；上游仍有个别机器 HCI 初始化超时的报告，
  真遇到时换 Intel BE200/AX210 或插个 USB 蓝牙棒更快。
- **换内核**：DKMS 会自动重编，但**重编需要头文件**（联网或把 deb 放进 `debs/`）。
  重编失败时 btusb 退回发行版原版 —— 只有蓝牙失效，**WiFi 不受影响**（ath12k 是内核自带的）。
- 内核 ≥ 6.13 后补丁模块多余：`sudo ./uninstall.sh`。

## 6. 常见故障速查

| 症状 | 大概率原因 | 处理 |
|------|-----------|------|
| `lspci` 里没有 `17cb:1107` | 卡没通电/被 BIOS 屏蔽/在虚拟机里 | `rfkill list`、BIOS 里找 WLAN；虚拟机无 PCIe 直通 |
| 有卡、没有 `wlan0`，`dmesg` 报 `failed to load firmware` | 固件缺 | `./scripts/fetch-firmware.sh` 或 `install.sh` |
| `dmesg` 报 `ath12k ... invalid firmware` | 固件版本与内核不匹配 | 更新内核或换回发行版 `linux-firmware` |
| 6 GHz 看不到 | 国家码/regdb | `sudo iw reg set CN`，`iw reg get` 确认 |
| `modinfo btusb` 没有 `2C7C` | 补丁模块没装上/被内核更新冲掉 | 重跑 `install.sh` |
| `insmod: Key was rejected by service` | Secure Boot 未注册 MOK | 第 4 节 |
| `hci0` 起不来，`Opcode 0x0c03 failed: -110` | 这张 USB 蓝牙通道个别机器不配合 | 换 Intel BE200/AX210 或 USB 蓝牙棒 |
| `dkms build failed` | 缺内核头文件 | `apt install linux-headers-$(uname -r)` 后重跑 |
| 装了补丁后蓝牙仍无 `hci0` | 设备没被识别成 USB | `lsusb \| grep 2c7c` 先确认 |

## 7. 仓库结构

```
install.sh                      # 主安装脚本（联网）
install-offline.sh              # 离线安装：dpkg -i debs/ + FC_OFFLINE=1 跑 install.sh
verify.sh / uninstall.sh / lib.sh
btusb/
  src-6.8/                      # 发行版 6.8 btusb 源码 + 已加的 2c7c 条目（GPL-2.0）
  patch_btusb.py                # 幂等补丁（其它内核版本复用）
scripts/
  build-btusb-from-source.sh    # 非 6.8 内核：取本机内核源码编译
  fetch-firmware.sh             # 下载 21 个固件到 firmware/
  fetch-debs.sh                 # 预下载 dkms/头文件等到 debs/
tests/run.sh                    # 静态自检（CI 跑的就是它）
.github/workflows/ci.yml        # shellcheck + 自检 + 链接检查
```

## 8. 许可

- `btusb/` 下的内核源码：**GPL-2.0**（来自 Linux 6.8，见 `NOTICE`）。
- 本仓库的脚本：**GPL-2.0**（见 `LICENSE`）。
- `firmware/` 里的固件：Qualcomm 专有，按 linux-firmware 的条款可再分发，
  但**不属于** GPL；仓库本身不跟踪这些二进制，用 `scripts/fetch-firmware.sh` 现取。
- 详细来源与条款见 [NOTICE](NOTICE)。

## 9. 参与

- 遇到问题：[开 issue](https://github.com/wjh-ux/fastconnect7800-linux/issues/new/choose)，
  模板会要求你贴 `./verify.sh` 的输出 —— 没有硬件信息的 issue 基本没法查。
- 想改代码：先看 [CONTRIBUTING.md](CONTRIBUTING.md)，提交前跑 `bash tests/run.sh`。
- 安全相关（脚本提权、供应链）：见 [SECURITY.md](SECURITY.md)，别开公开 issue。
- 版本变化：[CHANGELOG.md](CHANGELOG.md)。
- 最有用的贡献其实是**机型反馈**：`hci0` 起不起得来、6 GHz 能不能上，这两个数据点
  比代码更稀缺。

## 10. 参考

- 上游加入该 ID 的提交（v6.13）：
  `a6587d7ed2cd8` — *Bluetooth: btusb: Add ID 0x2c7c:0x0130 for Qualcomm WCN785x*
- 该 ID 未进旧内核导致的问题报告：
  <https://lore.kernel.org/linux-bluetooth/5b62963c833862dc522b219ff5f5619991eb958a.camel@t-online.de/T/>
- 固件来源：<https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/ath12k/WCN7850/hw2.0>

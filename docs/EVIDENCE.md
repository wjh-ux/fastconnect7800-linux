# 验证记录 / Evidence

两类证据分开写，避免把“编译通过”说成“硬件可用”。

## A. 真机（硬件层）

| 项目 | 结果 | 来源 |
|---|---|---|
| WiFi 7 关联 ASUS RT-BE88U 并上网 | ✅ | 维护者实测（Ubuntu 22.04.5 / 6.8.0-138，便携盘原生启动） |
| 蓝牙鼠标连接并工作 | ✅ | 同上 |
| 蓝牙耳机连接并工作 | ✅ | 同上 |
| 机型、`dmesg`、截图 | ❌ 未留存 | 当时只记录了结果，没有截图，不补造 |

复核方法见 [EXPECTED.md](EXPECTED.md)；具体机型请在 [COMPATIBILITY.md](../COMPATIBILITY.md)
里补一行。

## B. 构建与安装层（任何人可复现）

以下全部在 **VMware 客户机**（Ubuntu 22.04.5 / 6.8.0-138，无 PCIe 直通）上取得，
命令和输出都是当时的原文。

### B1. 编译产物确实带上了三个 ID

```
$ modinfo btusb | grep -E '^filename|v2C7C'
filename:       /lib/modules/6.8.0-138-generic/updates/dkms/btusb.ko
alias:          usb:v2C7Cp0132d*dc*dsc*dp*ic*isc*ip*in*
alias:          usb:v2C7Cp0131d*dc*dsc*dp*ic*isc*ip*in*
alias:          usb:v2C7Cp0130d*dc*dsc*dp*ic*isc*ip*in*
```

（发行版原版模块里 `grep -c v2C7C` 是 0，这是补丁生效的直接证据。）

### B2. 两种编译路径都成立

```
$ dkms status
btusb-fastconnect/1.0, 6.8.0-138-generic, x86_64: installed

# 另一条：没有 dkms 时的一次性 make
$ FC_NO_DKMS=1 sudo ./install.sh
  OK module signed with MOK.priv
  OK installed /lib/modules/6.8.0-138-generic/updates/btusb.ko
  OK btusb now advertises 2c7c:0130
```

### B3. 固件 21 个文件、哈希逐个匹配

```
$ ./scripts/fetch-firmware.sh
  ok   ath12k/WCN7850/hw2.0/amss.bin                  6090816 bytes
  ok   ath12k/WCN7850/hw2.0/m3.bin                     299660 bytes
  ok   ath12k/WCN7850/hw2.0/board-2.bin               2431968 bytes
  ok   qca/rampatch_usb_00190200.bin                   250276 bytes
  ...
all 21 files present and matching firmware/SHA256SUMS
```

### B4. Secure Boot 是唯一的拦路虎（预期行为）

```
$ sudo insmod btusb.ko
insmod: ERROR: could not insert module btusb.ko: Key was rejected by service
$ sudo dmesg | tail -2
[...] Loading of unsigned module is rejected
[...] Loading of module with unavailable key is rejected
```

签名本身是成功的（`modinfo -F signer` 有输出），缺的是 MOK 注册 —— 即 README 第 4 节。

### B5. 虚拟机看不到卡（也是预期行为，用来排除误判）

```
$ lspci -nn | grep 17cb      # 无输出
$ lsusb    | grep 2c7c       # 无输出
$ cat /sys/class/dmi/id/product_name
VMware20,1
```

如果你在虚拟机里测，看到这一节的输出而报“驱动不工作”，那就是误判 —— 虚拟机没有
PCIe 直通，卡根本不在里面。

## 怎么自己补一份证据

```bash
./verify.sh > verify-$(date +%F).txt
sudo dmesg | grep -iE 'ath12k|btusb|firmware' > dmesg-$(date +%F).txt
uname -r; lsb_release -ds
```

把这些贴进 issue 或直接提 PR 加到 COMPATIBILITY.md，比自己说“能用”有用得多。

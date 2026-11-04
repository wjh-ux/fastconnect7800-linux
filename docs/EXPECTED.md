# 什么算“装好了” / What success looks like

这里只列**判断标准**，不编造日志。每条命令后面写的是“应该看到什么形状”，
具体数字（MAC、PCI 地址、wiphy 编号）因机而异。

## 1. 硬件被内核看见

```bash
lspci -nn | grep 17cb        # 17cb:1107  ← 这是 WiFi 的那一半
lsusb    | grep 2c7c         # 2c7c:0130  ← 这是蓝牙的那一半
```

两行都在 = 卡通电、BIOS 没屏蔽、不在那种没有直通的虚拟机里。

## 2. 驱动认领了设备

```bash
lspci -nnk | grep -A3 17cb           # 应该出现  Kernel driver in use: ath12k
modinfo ath12k | grep 17CB           # 有 pci:v000017CBd00001107 的 alias
modinfo btusb  | grep 2C7C           # 有 0130/0131/0132 三条（打过补丁才有）
```

若 `lspci -nnk` 显示 `Kernel driver in use:` 为空或 `ath11k`，说明驱动没绑上，
看 `dmesg | grep -i ath12k`。

## 3. 固件加载成功

```bash
sudo dmesg | grep -iE 'ath12k|firmware' | tail -20
```

要看到的是 **成功** 的痕迹：`direct-loading`、`firmware` 相关行没有 `failed`/`-2`。
出现 `failed to load` / `request_firmware ... failed` 就是缺文件，回第 3 节装固件。

## 4. WiFi 真的能用

```bash
iw dev                    # 有 Interface wlan0（或 wlp*/wlx*）+ phy#N
iw phy | head -30         # Band 1 / Band 2 / Band 4 的频段表
rfkill list               # wlan 不是 soft/hard blocked
nmcli device status       # wlan0: disconnected/connected
```

连上以后：

```bash
iw dev wlan0 link         # SSID、freq、信号强度
ip -4 addr show wlan0     # 拿到 IPv4
ping -c3 1.1.1.1
```

## 5. 蓝牙真的能用

```bash
bluetoothctl show         # 有 Controller XX:XX:.. + Powered: yes
bluetoothctl list         # 列出 hci0 的地址
bluetoothctl devices      # 已配对设备
```

真正的成功标志是**鼠标能动了、耳机能出声**，不是只有 `hci0`。
`hci0` 起来了但连不上，通常看 `dmesg | grep -i bluetooth` 里的
`Failed to ...`/`timeout`。

## 6. 重启后仍然可用（最容易被忽略的一条）

```bash
sudo reboot
# 起来后
iw dev && bluetoothctl list && modinfo btusb | grep -c 2C7C
```

很多人栽在这里：`modprobe` 当时能用，重启后 Secure Boot 又把模块拒了，或者
DKMS 在换内核后没编出来。第 6 条过了才算真的“装好了”。

## 出问题时要带什么

```bash
./verify.sh                                  # 完整输出
sudo dmesg | grep -iE 'ath12k|btusb|firmware' | tail -50
uname -r; lsb_release -ds
```

这三样贴进 issue，比“WiFi 用不了”有用一百倍。

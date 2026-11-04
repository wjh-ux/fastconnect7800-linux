# 兼容性 / Compatibility

一台机器一行。**只有真正跑过的才填**，没验证过的机型不要猜。
One row per machine. Only list what was actually tested — no guesses.

| 机器 / Machine | 模块 | 发行版 / Kernel | WiFi | 蓝牙 / BT | 备注 |
|---|---|---|---|---|---|
| Dell Inspiron 7405 2-in-1（`0P76G3`，BIOS 1.20.0） | NCM865 · `17cb:1107` / `2c7c:0130` | Ubuntu 22.04.5 · 6.8.0-138-generic | ✅ ASUS RT-BE88U | ✅ 鼠标 + 耳机 | 首个验证记录；Ubuntu To Go 便携盘原生启动；DKMS 补丁模块 |
| _(你的机器)_ | | | | | |

用 `./scripts/report-machine.sh` 生成你那一行，见下面「怎么加一行」。

## 怎么加一行

1. 在目标机上装好（`sudo ./install.sh`），**按 README 第 4 节处理完 Secure Boot 并重启**；
2. 跑一条命令，它会直接打印出可粘贴的表格行：

```bash
./scripts/report-machine.sh                 # 打印表格行 + 明细
./scripts/report-machine.sh --save ~/fc-report   # 顺便把日志存成文件，便于开 issue
```

3. 把输出第一行（`| 机型 | NCM865 · … |`）贴进上面表格，或开 issue 附上
   `--save` 目录里的内容。需要手工核对时：

```bash
./verify.sh                                   # 驱动与固件状态
cat /sys/class/dmi/id/product_name            # 机型
bluetoothctl list; dmesg | grep -i btusb      # 蓝牙到底有没有起来
iw phy | grep -A12 'Band 4'                   # 6 GHz 是否在信道表里
```

## 目前已知的“能用/不能用”边界

| 场景 | 结果 | 说明 |
|---|---|---|
| 原生启动 Ubuntu 22.04 + 6.8 | ✅ | WiFi + 蓝牙均正常（本仓库的主要验证场景） |
| Ubuntu 24.04（6.8） | 预期 ✅ | 同一份 6.8 源码，未实机验证 |
| Debian 12 + backports 6.12 | 预期 ✅ | 走 `build-btusb-from-source.sh`，未实机验证 |
| Debian 13（6.12） | 预期 ✅ | 同上 |
| 内核 ≥ 6.13 | ✅ 无需补丁 | `2c7c:0130` 已进主线 |
| VMware / VirtualBox 无直通 | ❌ | PCIe 设备无法直通，装什么都没用；蓝牙可 USB 直通 |
| 6 GHz | 视国家码 | `iw reg set CN` 后再看，`wireless-regdb` 太旧会没有 Band 4 |
| MLO（WiFi 7 多链路） | 部分可用 | 取决于内核版本，2.4/5 GHz 最稳 |

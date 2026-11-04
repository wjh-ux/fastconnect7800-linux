# Contributing

Thanks for looking at this. The scope is deliberately narrow: **make the Qualcomm
FastConnect 7800 (WCN7850 / NCM865) behave on Ubuntu and Debian, and nothing else.**

## 最有用的贡献：机型反馈

如果你的机器不是 ThinkPad / ROG 之类我已经测过的型号，最有价值的是**一条带诊断信息的
issue**，特别是：

- 蓝牙在 `hci0` 阶段是否失败（`dmesg | grep -i btusb` 里有没有 `Opcode 0x0c03 failed: -110`）
- WiFi 是否能上 6 GHz（`iw phy | grep -A6 'Band 4'`、`iw reg get`）
- 内核版本 + 发行版版本 + 模块型号（NCM865 / 其它）

请附上 `./verify.sh` 的完整输出，它已经把该看的都收集好了。

## 本地检查

提交前跑一遍（不需要 root、不需要网、不需要硬件）：

```bash
bash tests/run.sh
shellcheck -S error install.sh install-offline.sh verify.sh uninstall.sh lib.sh scripts/*.sh
```

两条都得是绿的，CI 用的是同一套。

## 改代码时请注意

1. **`btusb/src-6.8/` 是内核源码快照**，除非要跟随新的发行版内核，否则不要改它；
   增加设备 ID 请改 `btusb/patch_btusb.py`，它对任何版本的 `btusb.c` 都能用。
2. **别把固件二进制提交进 git**（`firmware/` 已被 `.gitignore` 排除）。固件是
   Qualcomm 专有代码，按 linux-firmware 条款分发，走 `scripts/fetch-firmware.sh`。
3. 脚本必须 **LF 换行**、**带 +x**（`.gitattributes` 与 `git update-index --chmod=+x` 已处理，
   但新加文件时记得）。
4. 新增功能要给 `install-offline.sh` 留一条“没有网络”的路径 —— 这个项目一半的用户
   是在 WiFi 还没起来的时候用它的。
5. 不要引入需要编译的依赖，也不要 `curl | sudo bash` 这种模式。

## 提交信息

一句话说清「哪个内核/发行版上、什么问题、怎么改的」，例如：

```
btusb: also match 2c7c:0132 (WCN785x variant)

Fixes: #12
```

## 许可

提交即表示你同意以 GPL-2.0 授权你的改动（脚本部分）或 GPL-2.0 兼容条款（内核源码部分），
见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

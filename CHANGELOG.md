# Changelog

## v1.0.1 — 2026-11-04

审计后的一轮修补（第一次发布后的自查）：

- **修**：仓库里所有脚本的权限位是 `100644`，`git clone` 下来 `sudo ./install.sh`
  会 Permission denied → 全部改为 `100755`。
- **修**：`install_firmware()` 会把 `firmware/.gitkeep` 也拷进 `/lib/firmware`。
- **修**：`build-btusb-from-source.sh` 只认 `/etc/apt/sources.list` 的一行式格式，
  在 Ubuntu ≥ 24.04 / Debian ≥ 13 的 deb822（`*.sources`）上直接失败 → 现在两种格式都支持。
- 新增：`tests/run.sh`（语法 / LF / 可执行位 / ID 数量 / 补丁幂等性）与 GitHub Actions CI。
- 新增：`CONTRIBUTING.md`、`SECURITY.md`、issue 模板、本文件。
- 文档：README 增加徽章、故障排查表、校验下载文件的方法。

## v1.0 — 2026-11-04

首个版本，真机验证（Ubuntu 22.04.5 / 6.8.0-138）：

- WiFi 7 通过 `ath12k` 连接 ASUS RT-BE88U，正常上网；
- 蓝牙鼠标、蓝牙耳机连接并正常工作；
- 固件 21 个文件、DKMS 补丁 `btusb`（`2c7c:0130/0131/0132`）、
  离线安装路径（`install-offline.sh` + `debs/`）均验证通过。

# Changelog

## v1.1.0 — 2026-11-04

把第一版缺的“项目配套”补齐。没有改驱动逻辑。

- **英文文档**：新增 `README.en.md`（与中文版结构一一对应），两个版本顶部互相切换。
- **固件哈希固定**：新增 `firmware/SHA256SUMS`（21 个 blob 的 SHA256，入库），
  `scripts/fetch-firmware.sh` 下载后逐条校验；上游固件变了会**拒绝安装并打印新哈希**，
  要接受得显式 `FC_ALLOW_NEW_FW=1`。
- **机型兼容性表**：`COMPATIBILITY.md`，一台机器一行，附“怎么加一行”的诊断命令。
- **验收标准**：`docs/EXPECTED.md`，写清“什么算装好了”，包括最容易被漏掉的
  “重启后仍然可用”这一条。
- **发布自动化**：`.github/workflows/release.yml`，推 `v*` tag 即自动
  打包（仓库 + 校验过的固件）→ 生成 `SHA256SUMS` → 建 Release。
  bundle 里不含 deb（内核头文件绑定内核 ABI，只能在目标机上取）。
- **CI 加严**：shellcheck 从 `error` 提到 `info` 级并全量清零（修了 15 条
  SC2015 / SC2012 / SC1091）；新增 4 个发行版的容器矩阵
  （ubuntu:22.04 / 24.04、debian:12 / 13），在各自 bash 上跑同一套自检。
- **自检扩充**：`tests/run.sh` 现在也查固件清单条数与关键 blob 是否被钉住。

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

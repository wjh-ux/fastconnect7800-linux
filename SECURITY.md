# Security

## 这个项目会碰哪些“敏感”的东西

安装脚本用 root 运行，会做这些事 —— 都请先看清楚再执行：

| 动作 | 位置 | 说明 |
|------|------|------|
| 写固件 | `/lib/firmware/ath12k/…`, `/lib/firmware/qca/…` | 已存在的旧文件会留 `.fc-backup` |
| 装内核模块 | `/lib/modules/$(uname -r)/updates/…` | 只替换 `btusb`，不动内核本体 |
| DKMS 注册 | `/usr/src/btusb-fastconnect-1.0/`, `/var/lib/dkms/…` | 换内核自动重编 |
| 签名 | `/var/lib/shim-signed/mok/MOK.{priv,der}` | 用发行版自带 MOK，不生成新密钥 |
| 改 apt 源 | `/etc/apt/sources.list.d/fastconnect-src.*` | 只在 `build-btusb-from-source.sh` 里，为了取内核源码 |

脚本**不会**：下载并执行远程脚本、改 `sudoers`、关防火墙、上传任何数据。

## 供应链

- 固件从 linux-firmware 主线取（`scripts/fetch-firmware.sh`），脚本会拒绝 HTML 应答，
  但**不做签名校验**。要更强保证就自己对照 linux-firmware 的 `WHENCE` 哈希。
- 内核源码来自你本机的发行版源（`apt-get source`），与已安装内核版本一致。
- 离线包的 SHA256 随 Release 一起发布，下载后请核对：

  ```bash
  sha256sum -c SHA256SUMS
  ```

## 报告问题

发现脚本会破坏系统、提权、或从不可信源拉东西 —— 请**不要开公开 issue**，
走 GitHub 的 [Private vulnerability reporting](../../security/advisories/new)，
或直接给维护者发邮件。普通 bug（驱动不工作、机型不兼容）开 issue 就行。

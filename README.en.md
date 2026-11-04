# FastConnect 7800 (WCN7850 / NCM865) on Ubuntu & Debian

[English](README.en.md) · [中文](README.md)

[![ci](https://github.com/wjh-ux/fastconnect7800-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/wjh-ux/fastconnect7800-linux/actions/workflows/ci.yml)
[![license: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue.svg)](LICENSE)
![platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-informational)
![kernel](https://img.shields.io/badge/kernel-%E2%89%A5%206.8%20%2F%20BT%20%E2%89%A5%206.13-lightgrey)

WiFi 7 + Bluetooth setup for the **Qualcomm FastConnect 7800** — the M.2 module Windows
reports as *"Qualcomm FastConnect 7800 Wi-Fi 7 High Band Simultaneous (HBS) Network
Adapter"*, i.e. **WCN7850** silicon on an **NCM865** module (PCI `17cb:1107`, Bluetooth USB
`2c7c:0130`).

**TL;DR** — WiFi needs no driver: the in-tree `ath12k` driver plus the
`ath12k/WCN7850/hw2.0` firmware on kernel ≥ 6.8 and you are done. Bluetooth is the annoying
half: `btusb` only learned the USB ID `2c7c:0130` in **v6.13**, so older kernels
(Ubuntu 22.04/24.04 = 6.8, Debian 12 = 6.1/6.12) match it as a generic USB dongle, skip the
QCA firmware download and end with `hci0: Opcode 0x0c03 failed: -110`. This repo adds that
one ID as a DKMS module and ships the firmware.

> Verified on real hardware (Ubuntu 22.04.5 / 6.8.0-138): WiFi 7 associates with an ASUS
> RT-BE88U, a Bluetooth mouse and a Bluetooth headset both connect and work.
> Machine matrix: [COMPATIBILITY.md](COMPATIBILITY.md). Reproducible build/install
> evidence: [docs/EVIDENCE.md](docs/EVIDENCE.md).

---

## 1. Identify the card first

| Function | Bus / ID | Driver | Module | Status |
|----------|----------|--------|--------|--------|
| WiFi 7 | PCI `17cb:1107` (subsystem varies by module, e.g. `80001EAC`) | `ath12k` | `ath12k` | supported upstream, firmware needed |
| Bluetooth | USB `2c7c:0130` (Quectel NCM865) | `btusb` | `btusb` | native from kernel 6.13, ID patch below that |

Required firmware (names are hard-coded in the drivers, do not rename):

```
/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin      # WiFi
/lib/firmware/ath12k/WCN7850/hw2.0/m3.bin
/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
/lib/firmware/qca/rampatch_usb_00190200.bin      # Bluetooth (name comes from ROM 0x00190200)
/lib/firmware/qca/nvm_usb_00190200.bin
```

## 2. Quick start

```bash
git clone https://github.com/wjh-ux/fastconnect7800-linux.git
cd fastconnect7800-linux
sudo ./install.sh          # needs network: fetches firmware, installs dkms/headers if missing
```

No network at all (e.g. booting Ubuntu To Go on the laptop before WiFi works):

```bash
# on a machine of the same distro release, with network:
./scripts/fetch-firmware.sh
sudo ./scripts/fetch-debs.sh

# copy everything over, then on the target:
sudo ./install-offline.sh
```

Prefer not running scripts? [Releases](https://github.com/wjh-ux/fastconnect7800-linux/releases)
carry a bundle with the firmware included. Verify it first:

```bash
sha256sum -c SHA256SUMS
```

## 2.1 Requirements

- Ubuntu 22.04 / 24.04, Debian 12 (the script pulls a 6.12 backports kernel) or 13
- Kernel ≥ 6.8 (that is where `ath12k` gained WCN7850 support)
- `sudo`, and write access to `/lib/firmware` and `/lib/modules`
- The machine must be the one the card is physically in — a VM without PCIe passthrough
  cannot use it, no matter what you install

## 3. What `install.sh` does

1. **Firmware** — copies `firmware/` into `/lib/firmware` (skips identical files, keeps a
   `.fc-backup` of anything it overwrites). An empty `firmware/` triggers
   `scripts/fetch-firmware.sh`.
2. **Kernel** — below 6.8 it installs `linux-generic-hwe-XX.04` (Ubuntu) or adds
   `bookworm-backports` and installs 6.12 (Debian), then asks you to reboot and re-run.
3. **btusb** — in this order:
   - kernel already knows `2c7c:0130` (≥ 6.13) → nothing to do;
   - 6.8.x with dkms → DKMS module, `AUTOINSTALL=yes`, rebuilt on kernel upgrades;
   - 6.8.x without dkms (offline/minimal system) → one-shot `make`, installed into
     `/lib/modules/$(uname -r)/updates/`;
   - any other kernel → `scripts/build-btusb-from-source.sh`: `apt-get source` for **exactly
     the running kernel**, apply the same patch, build only `btusb.ko`.

Both build paths sign the module with the distro MOK key.

## 4. Secure Boot (the one manual step)

A self-built module is rejected unless its key is enrolled:

```
Loading of unsigned module is rejected
Loading of module with unavailable key is rejected
```

DKMS signs with `/var/lib/shim-signed/mok/MOK.{priv,der}`, but that key has to be enrolled
in firmware once:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der   # pick a one-time password
sudo reboot
# at the blue MokManager screen: Enroll MOK -> Continue -> Yes -> password -> Reboot
mokutil --test-key /var/lib/shim-signed/mok/MOK.der      # ... is already enrolled
```

Or just turn Secure Boot off in the firmware settings. Note the MOK list lives in **NVRAM**,
so it does not travel with the disk.

## 5. Verify

```bash
./verify.sh
```

The first two sections are what matter:

```
1) hardware visible to this kernel
0000:03:00.0 Network controller [0280]: Qualcomm ... [17cb:1107]
Bus 003 Device 005: ID 2c7c:0130 Quectel ...

2) drivers
  ath12k : /lib/modules/6.8.0-138-generic/kernel/drivers/net/wireless/ath/ath12k/ath12k.ko
  btusb  : /lib/modules/6.8.0-138-generic/updates/dkms/btusb.ko
  OK btusb advertises 2c7c:0130
```

Then the real thing:

```bash
iw dev                      # wlan0
bluetoothctl list           # hci0
```

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| no `17cb:1107` in `lspci` | card unpowered / disabled in firmware / inside a VM | check `rfkill`, BIOS WLAN setting; VMs have no PCIe passthrough |
| card present, no `wlan0`, `failed to load firmware` | firmware missing | `./scripts/fetch-firmware.sh`, or `install.sh` |
| `ath12k ... invalid firmware` | firmware/kernel mismatch | update the kernel or fall back to the distro `linux-firmware` |
| no 6 GHz | regulatory db / country code | `sudo iw reg set CN`, confirm with `iw reg get` |
| `modinfo btusb` has no `2C7C` | patch module missing or lost in a kernel upgrade | re-run `install.sh` |
| `insmod: Key was rejected by service` | Secure Boot, MOK not enrolled | section 4 |
| `hci0` never appears, `Opcode 0x0c03 failed: -110` | this USB BT path misbehaves on some machines | swap to Intel BE200/AX210, or use a USB BT dongle |
| `dkms build failed` | kernel headers missing | `apt install linux-headers-$(uname -r)` and re-run |
| patched, but still no `hci0` | device not enumerated as USB | check `lsusb \| grep 2c7c` first |

## 7. Known limits

- **6 GHz / WiFi 7 (EHT/MLO)**: `ath12k` works, but 6 GHz needs `wireless-regdb` and a
  sensible country code (`sudo iw reg set CN`); MLO is still wobbly on some kernels.
  2.4/5 GHz is the safe path.
- **Bluetooth**: verified working with a mouse and a headset on this module; upstream still
  has reports of HCI init timeouts on other machines.
- **Kernel upgrades**: DKMS rebuilds automatically, but the rebuild **needs headers**
  (network, or matching debs in `debs/`). If it fails, btusb falls back to the stock module —
  Bluetooth stops working, **WiFi keeps working** (`ath12k` is in-tree and only needs firmware).
- **Kernel ≥ 6.13**: the patch module is redundant, `sudo ./uninstall.sh` removes it.

## 8. Repository layout

```
install.sh                      # main installer (needs network)
install-offline.sh              # offline: dpkg -i debs/ then install.sh with FC_OFFLINE=1
verify.sh / uninstall.sh / lib.sh
btusb/
  src-6.8/                      # distro 6.8 btusb source + the three 2c7c IDs (GPL-2.0)
  patch_btusb.py                # idempotent patch, works on any kernel version
scripts/
  build-btusb-from-source.sh    # non-6.8 kernels: build from the distro's own source
  fetch-firmware.sh             # download the 21 blobs, verify against firmware/SHA256SUMS
  fetch-debs.sh                 # pre-download dkms/headers into debs/
tests/run.sh                    # static self-check (this is what CI runs)
docs/EXPECTED.md                # acceptance criteria
COMPATIBILITY.md                # machine matrix
.github/workflows/              # ci.yml + release.yml
```

## 9. Licence

- Kernel sources under `btusb/`: **GPL-2.0** (from Linux 6.8, see `NOTICE`).
- Scripts: **GPL-2.0** (see `LICENSE`).
- Firmware in `firmware/`: proprietary Qualcomm, redistributable under the linux-firmware
  terms, **not** GPL. The binaries are not tracked in git; `scripts/fetch-firmware.sh` pins
  their SHA256 in `firmware/SHA256SUMS`.
- Details: [NOTICE](NOTICE).

## 10. Contributing

- Bugs: [open an issue](https://github.com/wjh-ux/fastconnect7800-linux/issues/new/choose) —
  the template asks for `./verify.sh` output, without it there is little to go on.
- Patches: read [CONTRIBUTING.md](CONTRIBUTING.md), run `bash tests/run.sh` first.
- Security (script privilege, supply chain): see [SECURITY.md](SECURITY.md), not a public issue.
- Changes: [CHANGELOG.md](CHANGELOG.md).
- Machine reports are the most valuable contribution: whether `hci0` comes up and whether
  6 GHz works are the two data points nobody has enough of.

## 11. References

- Upstream commit that added the ID (v6.13):
  `a6587d7ed2cd8` — *Bluetooth: btusb: Add ID 0x2c7c:0x0130 for Qualcomm WCN785x*
- Bug report for the same ID on older kernels:
  <https://lore.kernel.org/linux-bluetooth/5b62963c833862dc522b219ff5f5619991eb958a.camel@t-online.de/T/>
- Firmware source: <https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/ath12k/WCN7850/hw2.0>

#!/usr/bin/env python3
"""Add the Qualcomm FastConnect 7800 / Quectel NCM865 USB IDs to btusb.c.

Used by install-*.sh and build-btusb-from-source.sh.  Idempotent.

The IDs are 2c7c:0130 (and the sibling variants 0131/0132) which is what the
WCN785x based NCM865 module exposes over USB.  Mainline added 2c7c:0130 in
v6.13 (commit a6587d7ed2cd8); every distro kernel older than that needs this
entry, otherwise btusb binds the device through the generic USB class match
and never runs the QCA firmware download -> hci0 reset timeouts.
"""
import re
import sys

ENTRY = """
	/* Quectel NCM865 / Qualcomm WCN785x (FastConnect 7800) */
	{ USB_DEVICE(0x2c7c, 0x0130), .driver_info = BTUSB_QCA_WCN6855 |
						     BTUSB_WIDEBAND_SPEECH },
	{ USB_DEVICE(0x2c7c, 0x0131), .driver_info = BTUSB_QCA_WCN6855 |
						     BTUSB_WIDEBAND_SPEECH },
	{ USB_DEVICE(0x2c7c, 0x0132), .driver_info = BTUSB_QCA_WCN6855 |
						     BTUSB_WIDEBAND_SPEECH },
"""


def main(path: str) -> int:
    src = open(path, encoding="utf-8", errors="surrogateescape").read()

    if "0x2c7c, 0x0130" in src:
        print("  already patched: %s" % path)
        return 0

    start = src.find("static const struct usb_device_id btusb_table[] = {")
    if start < 0:
        print("  ERROR: btusb_table not found in %s" % path, file=sys.stderr)
        return 1

    end = src.find("\n};\n", start)
    if end < 0:
        print("  ERROR: end of btusb_table not found", file=sys.stderr)
        return 1

    out = src[:end] + "\n" + ENTRY + src[end:]
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print("  patched: %s" % path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: patch_btusb.py <btusb.c>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

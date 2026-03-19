#!/usr/bin/env python3
"""Patch the BIP ignition's install-to-disk.sh to add --copy-network.

Without --copy-network, coreos-installer install does not carry the live
environment's NetworkManager keyfiles to the installed system.  On Hetzner
servers with static IPs (no DHCP), the installed system would lose network
connectivity after the install-to-disk reboot.

Usage: patch-install-to-disk.py <path-to-bip-ignition.ign>

The file is modified in-place.  Stdout prints PATCHED or SKIPPED.
"""

import base64
import json
import sys
import urllib.parse

SCRIPT_PATH = "/usr/local/bin/install-to-disk.sh"
MARKER = "--copy-network"


def decode_data_url(data_url: str) -> str:
    if ";base64," in data_url:
        _, encoded = data_url.split(";base64,", 1)
        return base64.b64decode(encoded).decode("utf-8")
    if "," in data_url:
        _, raw = data_url.split(",", 1)
        return urllib.parse.unquote(raw)
    raise ValueError(f"Unknown data URL format: {data_url[:80]}")


def encode_data_url(content: str) -> str:
    encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
    return f"data:text/plain;charset=utf-8;base64,{encoded}"


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <ignition-file>", file=sys.stderr)
        sys.exit(1)

    ign_path = sys.argv[1]

    with open(ign_path, "r") as f:
        ign = json.load(f)

    patched = False
    for file_entry in ign.get("storage", {}).get("files", []):
        if file_entry.get("path") != SCRIPT_PATH:
            continue

        source = file_entry.get("contents", {}).get("source", "")
        script = decode_data_url(source)

        if MARKER in script:
            print("SKIPPED: install-to-disk.sh already contains --copy-network")
            return

        # Add --copy-network to the coreos-installer install command
        script = script.replace(
            "coreos-installer install -n -i",
            "coreos-installer install -n --copy-network -i",
        )

        file_entry["contents"]["source"] = encode_data_url(script)
        patched = True
        break

    if not patched:
        print(f"SKIPPED: {SCRIPT_PATH} not found in ignition storage.files")
        return

    with open(ign_path, "w") as f:
        json.dump(ign, f, separators=(",", ":"))

    print("PATCHED: Added --copy-network to install-to-disk.sh")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Prints the UDID of the iPhone simulator CI runs on: iPhone 17 Pro (402 × 874 pt, iOS design I2)
# on the newest iOS runtime, else the newest iPhone available.
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json, re, sys

best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable", True) or not device["name"].startswith("iPhone"):
            continue
        score = (device["name"] == "iPhone 17 Pro", version)
        if best is None or score > best[0]:
            best = (score, device["udid"], device["name"])
if best is None:
    sys.exit("No iPhone simulator is available")
print(f"Simulator: {best[2]} on iOS {best[0][1][0]}.{best[0][1][1]}", file=sys.stderr)
print(best[1])
'

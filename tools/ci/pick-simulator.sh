#!/usr/bin/env bash
# Prints the UDID of the simulator CI runs on: iPhone 17 Pro (402 × 874 pt, iOS design I2) on the
# newest iOS runtime, else the newest iPhone available. With --ipad: the largest 13-inch iPad (the
# App Store's 13″ screenshots, doc "Delululand — iPad Layout" IP15), else the newest iPad.
set -euo pipefail

kind="iphone"
if [ "${1:-}" = "--ipad" ]; then kind="ipad"; fi

xcrun simctl list devices available --json | KIND="$kind" python3 -c '
import json, os, re, sys

kind = os.environ["KIND"]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        name = device["name"]
        if not device.get("isAvailable", True):
            continue
        if kind == "ipad":
            if not name.startswith("iPad"):
                continue
            score = ("13-inch" in name and "Pro" in name, "13-inch" in name, version)
        else:
            if not name.startswith("iPhone"):
                continue
            score = (name == "iPhone 17 Pro", version)
        if best is None or score > best[0]:
            best = (score, device["udid"], name)
if best is None:
    sys.exit(f"No {kind} simulator is available")
print(f"Simulator: {best[2]}", file=sys.stderr)
print(best[1])
'

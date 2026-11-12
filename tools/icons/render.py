#!/usr/bin/env python3
"""Renders the app icons, the launch mark and the asset-catalog colours.

Source of truth: iOS canvas "Delululand — iOS App Design", Foundations › App icon (envelope + terracotta
wax seal on paper; light, dark, tinted) and the launch screen (paper, the mark, the Literata wordmark).
The staging build adds a "TST" band so it can't be mistaken for production (decision Q9).

Needs: rsvg-convert, Pillow, and the bundled fonts installed for fontconfig (~/.fonts).
Run from the repo root: python3 tools/icons/render.py
"""
import json
import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")

LIGHT = dict(bg="#F5F0E8", body="#E8E1D8", flap="#DED5C9", edge="#C9BFB2", ink="#33323B",
             band="#202B45", band_ink="#FFFFFF")
DARK = dict(bg="#16181F", body="#332F2A", flap="#2B2823", edge="#4B463E", ink="#ECE6DC",
            band="#B4C2EA", band_ink="#141A2C")
SEAL = "#D99A82"


def envelope(c, x, y, w):
    """The mark (viewBox 100 × 72) placed at x, y with width w."""
    s = w / 100.0
    return f"""
  <g transform="translate({x} {y}) scale({s})">
    <rect x="3" y="3" width="94" height="66" rx="6" fill="{c['body']}" stroke="{c['edge']}" stroke-width="1.5"/>
    <path d="M3 6 L50 42 L97 6" fill="{c['flap']}" stroke="{c['edge']}" stroke-width="1.5" stroke-linejoin="round"/>
    <circle cx="50" cy="42" r="10" fill="{SEAL}"/>
    <circle cx="50" cy="42" r="6.5" fill="none" stroke="rgba(255,255,255,0.35)" stroke-width="1.5"/>
  </g>"""


def icon_svg(c, staging=False):
    size = 1024
    w = 683  # 120 / 180 of the icon, as drawn on the canvas
    h = w * 0.72
    x = (size - w) / 2
    y = (size - h) / 2 - (40 if staging else 0)
    band = ""
    if staging:
        band = f"""
  <rect x="0" y="770" width="{size}" height="150" fill="{c['band']}"/>
  <text x="{size / 2}" y="878" text-anchor="middle" font-family="Manrope" font-weight="800"
        font-size="104" letter-spacing="14" fill="{c['band_ink']}">TST</text>"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <rect width="{size}" height="{size}" fill="{c['bg']}"/>{envelope(c, x, y, w)}{band}
</svg>"""


def launch_svg(c, scale):
    # 64 × 46 mark, 12 pt gap, Literata SemiBold 18 pt wordmark (canvas launch screen).
    width, height = 180, 84
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width * scale}" height="{height * scale}" viewBox="0 0 {width} {height}">
  {envelope(c, (width - 64) / 2, 0, 64)}
  <text x="{width / 2}" y="78" text-anchor="middle" font-family="Literata" font-weight="600" font-size="18"
        fill="{c['ink']}">Delulutopia</text>
</svg>"""


def render(svg, out, mode="RGB"):
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        path = f.name
    png = out + ".tmp.png"
    subprocess.run(["rsvg-convert", "-o", png, path], check=True)
    os.unlink(path)
    img = Image.open(png)
    if mode == "RGB":
        img = img.convert("RGB")  # App Store icons must not carry alpha
    elif mode == "L":
        img = img.convert("L").convert("RGB")
    img.save(out, optimize=True)
    os.unlink(png)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def appicon(name, staging):
    d = os.path.join(ASSETS, f"{name}.appiconset")
    os.makedirs(d, exist_ok=True)
    render(icon_svg(LIGHT, staging), os.path.join(d, "icon-light.png"))
    render(icon_svg(DARK, staging), os.path.join(d, "icon-dark.png"))
    render(icon_svg(DARK, staging), os.path.join(d, "icon-tinted.png"), mode="L")
    base = {"idiom": "universal", "platform": "ios", "size": "1024x1024"}
    write_json(os.path.join(d, "Contents.json"), {
        "images": [
            {**base, "filename": "icon-light.png"},
            {**base, "filename": "icon-dark.png",
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
            {**base, "filename": "icon-tinted.png",
             "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
        ],
        "info": {"author": "xcode", "version": 1},
    })


def launch_mark():
    d = os.path.join(ASSETS, "LaunchMark.imageset")
    os.makedirs(d, exist_ok=True)
    images = []
    for theme, c in (("light", LIGHT), ("dark", DARK)):
        for scale in (1, 2, 3):
            fn = f"launch-mark-{theme}@{scale}x.png"
            render(launch_svg(c, scale), os.path.join(d, fn), mode="RGBA")
            entry = {"idiom": "universal", "filename": fn, "scale": f"{scale}x"}
            if theme == "dark":
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            images.append(entry)
    write_json(os.path.join(d, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1}})


def colorset(name, light, dark):
    d = os.path.join(ASSETS, f"{name}.colorset")
    os.makedirs(d, exist_ok=True)

    def comp(hexstr):
        h = hexstr.lstrip("#")
        return {"color-space": "srgb", "components": {
            "red": f"0x{h[0:2]}", "green": f"0x{h[2:4]}", "blue": f"0x{h[4:6]}", "alpha": "1.000"}}

    write_json(os.path.join(d, "Contents.json"), {
        "colors": [
            {"idiom": "universal", "color": comp(light)},
            {"idiom": "universal", "color": comp(dark),
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ],
        "info": {"author": "xcode", "version": 1},
    })


if __name__ == "__main__":
    os.makedirs(ASSETS, exist_ok=True)
    write_json(os.path.join(ASSETS, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    appicon("AppIcon", staging=False)
    appicon("AppIcon-Staging", staging=True)
    launch_mark()
    colorset("LaunchBackground", LIGHT["bg"], DARK["bg"])  # --dl-paper
    colorset("AccentColor", "#202B45", "#B4C2EA")  # --dl-seal
    print("rendered into", ASSETS)

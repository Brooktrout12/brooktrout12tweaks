#!/usr/bin/env python3
"""Rasterize the bundled simple vector icon; Pillow is a build-artwork dependency only."""
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
svg = ET.parse(root / "artwork/BatteryCapacity18.svg").getroot()
ns = {"s": "http://www.w3.org/2000/svg"}
size, scale = 29, 24
canvas = Image.new("RGBA", (size * scale, size * scale))
draw = ImageDraw.Draw(canvas)
stops = svg.findall("s:defs/s:linearGradient/s:stop", ns)
colors = [tuple(bytes.fromhex(stop.attrib["stop-color"].lstrip("#"))) for stop in stops]
for y in range(canvas.height):
    t = y / (canvas.height - 1)
    color = tuple(round(a * (1 - t) + b * t) for a, b in zip(*colors)) + (255,)
    draw.line((0, y, canvas.width, y), fill=color)
mask = Image.new("L", canvas.size)
md = ImageDraw.Draw(mask)
md.rounded_rectangle((0, 0, canvas.width - 1, canvas.height - 1), radius=6.4 * scale, fill=255)
canvas.putalpha(mask)
draw = ImageDraw.Draw(canvas)
for rect in svg.findall("s:rect", ns)[1:]:
    a = rect.attrib
    x, y, w, h, r = [float(a.get(k, 0)) for k in ("x", "y", "width", "height", "rx")]
    bounds = (x * scale, y * scale, (x + w) * scale, (y + h) * scale)
    if a.get("stroke"):
        # SVG strokes are centered on the rectangle path; Pillow strokes are inset.
        stroke = float(a["stroke-width"])
        bounds = ((x - stroke/2) * scale, (y - stroke/2) * scale,
                  (x + w + stroke/2) * scale, (y + h + stroke/2) * scale)
        draw.rounded_rectangle(bounds, radius=(r + stroke/2) * scale,
                               outline="white", width=round(stroke * scale))
    else:
        draw.rounded_rectangle(bounds, radius=r * scale, fill="white")

resources = root / "prefs/Resources"
loader = root / "layout/Library/PreferenceLoader/Preferences"
for factor in (1, 2, 3):
    suffix = "" if factor == 1 else f"@{factor}x"
    icon = resources / f"icon{suffix}.png"
    canvas.resize((size * factor, size * factor), Image.Resampling.LANCZOS).save(icon)
    shutil.copyfile(icon, loader / f"BatteryCapacity18{suffix}.png")
print("Created 29, 58 and 87 px icons in the preference bundle and loader directory.")

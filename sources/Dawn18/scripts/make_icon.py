#!/usr/bin/env python3
"""Render the original geometric Settings icon (requires Pillow).

The matching SVG is included for vector editing. No external artwork/fonts.
"""
from pathlib import Path
from PIL import Image, ImageDraw

resources = Path(__file__).resolve().parents[1] / "Resources"
factor = 4
canvas = Image.new("RGBA", (87 * factor, 87 * factor))
draw = ImageDraw.Draw(canvas)
def box(values):
    return tuple(round(x * factor) for x in values)
draw.rounded_rectangle(box((0, 0, 87, 87)), 19 * factor, fill="#4678e8")
draw.ellipse(box((16.5, 16.5, 70.5, 70.5)), fill="white")
draw.pieslice(box((16.5, 16.5, 70.5, 70.5)), 270, 90, fill="#182544")
draw.ellipse(box((29.5, 28.5, 36.5, 35.5)), fill="#4678e8")
draw.ellipse(box((50.5, 51.5, 57.5, 58.5)), fill="white")
for scale in (1, 2, 3):
    suffix = "" if scale == 1 else f"@{scale}x"
    canvas.resize((29 * scale, 29 * scale), Image.Resampling.LANCZOS).save(resources / f"icon{suffix}.png")

#!/usr/bin/env python3
"""Render the original vector-style Settings icon; requires Pillow only."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
destination = root / "layout/Library/PreferenceLoader/Preferences/CleanQuickActions"
factor = 4
canvas = Image.new("RGBA", (87 * factor, 87 * factor))
draw = ImageDraw.Draw(canvas)
def box(values):
    return tuple(round(x * factor) for x in values)
draw.rounded_rectangle(box((0, 0, 87, 87)), 19 * factor, fill="#168cba")
draw.rounded_rectangle(box((15, 14, 72, 73)), 12 * factor, fill="white")
for top, width in ((27, 25), (41, 21), (55, 28)):
    draw.rounded_rectangle(box((25, top, 25 + width, top + 5)), round(2.5 * factor), fill="#168cba")
    draw.ellipse(box((57, top - 0.5, 63, top + 5.5)), fill="#168cba")
for scale in (1, 2, 3):
    suffix = "" if scale == 1 else f"@{scale}x"
    canvas.resize((29 * scale, 29 * scale), Image.Resampling.LANCZOS).save(destination / f"icon{suffix}.png")

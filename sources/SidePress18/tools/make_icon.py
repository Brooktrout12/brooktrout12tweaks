#!/usr/bin/env python3
"""Render the original SidePress18 settings icon (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'prefs' / 'Resources'
size = 360
im = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(im)
for y in range(size):
    t = y / (size - 1)
    draw.line((0, y, size, y), fill=(int(37 - 24*t), int(116 - 40*t), int(239 - 47*t), 255))
mask = Image.new('L', (size, size))
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 359, 359), radius=77, fill=255)
im.putalpha(mask)
draw.rounded_rectangle((105, 53, 248, 309), radius=30, outline='white', width=14)
draw.rounded_rectangle((142, 74, 211, 86), radius=6, fill='white')
draw.rounded_rectangle((146, 280, 207, 288), radius=4, fill='white')
draw.rounded_rectangle((253, 123, 268, 188), radius=7, fill='white')
draw.ellipse((278, 112, 300, 134), fill=(169, 224, 255, 255))
draw.ellipse((302, 147, 324, 169), fill=(169, 224, 255, 255))
draw.rounded_rectangle((131, 153, 223, 217), radius=12, fill='white')
draw.rounded_rectangle((151, 141, 200, 165), radius=8, fill='white')
draw.ellipse((155, 163, 198, 206), fill=(21, 92, 211, 255))
draw.ellipse((165, 173, 188, 196), fill='white')
for scale in (1, 2, 3):
    name = 'Icon.png' if scale == 1 else f'Icon@{scale}x.png'
    im.resize((30*scale, 30*scale), Image.Resampling.LANCZOS).save(root / name)

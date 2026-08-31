#!/usr/bin/env python3
"""Generates a simple AppLock app icon (shield + fingerprint/lock) and builds an .icns."""
import os
from PIL import Image, ImageDraw

SIZES = [16, 32, 128, 256, 512]

def make(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size
    # Background: rounded shield gradient (two tones).
    def shield_bbox():
        return [s*0.08, s*0.08, s*0.92, s*0.92]
    x0, y0, x1, y1 = shield_bbox()
    # Simple two-tone background (top lighter blue, bottom darker).
    top = (77, 166, 255)     # light blue
    bottom = (35, 90, 200)   # deeper blue
    for i, py in enumerate(range(int(y0), int(y1))):
        t = (py - y0) / (y1 - y0)
        r = int(top[0] + (bottom[0]-top[0])*t)
        g = int(top[1] + (bottom[1]-top[1])*t)
        b = int(top[2] + (bottom[2]-top[2])*t)
        d.line([(x0, py), (x1, py)], fill=(r, g, b, 255))
    # Rounded corners: punch out by masking.
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    radius = s*0.22
    md.rounded_rectangle([0, 0, s-1, s-1], radius=radius, fill=255)
    # Cut the corners: apply mask by multiplying alpha.
    img.putalpha(255)
    black_bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    corner = Image.composite(img, black_bg, mask)
    img = corner

    d = ImageDraw.Draw(img)
    # A fingerprint / lock contour drawn as concentric white arcs in the middle.
    cx, cy = s*0.5, s*0.52
    w = s*0.06
    for r in [s*0.18, s*0.24]:
        d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(255, 255, 255, 255), width=int(w))
    # small horizontal "keyhole" bar at top.
    bw = s*0.18
    d.rounded_rectangle([cx-bw, cy-s*0.30, cx+bw, cy-s*0.14], radius=int(s*0.04), fill=(255,255,255,255))
    return img

os.makedirs("build/AppIcon.iconset", exist_ok=True)
for base in SIZES:
    for suf, px in (("", base), ("@2x", base*2)):
        name = f"icon_{base}x{base}{suf}.png"
        img = make(px)
        img.save(f"build/AppIcon.iconset/{name}")
# Build icns
os.system("iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns")
print("Wrote Resources/AppIcon.icns")

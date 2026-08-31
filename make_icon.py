#!/usr/bin/env python3
"""Build the macOS app icon from PrivyLock's canonical logo artwork."""

import os

from PIL import Image


SOURCE = "Resources/PrivyLockLogo.png"
ICONSET = "build/AppIcon.iconset"
SIZES = [16, 32, 128, 256, 512]


source = Image.open(SOURCE).convert("RGBA")
os.makedirs(ICONSET, exist_ok=True)

for base in SIZES:
    for suffix, pixels in (("", base), ("@2x", base * 2)):
        image = source.copy()
        image.thumbnail((pixels, pixels), Image.Resampling.LANCZOS)

        canvas = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
        offset = ((pixels - image.width) // 2, (pixels - image.height) // 2)
        canvas.alpha_composite(image, offset)
        canvas.save(os.path.join(ICONSET, f"icon_{base}x{base}{suffix}.png"))

os.system(f"iconutil -c icns {ICONSET} -o Resources/AppIcon.icns")
print(f"Wrote Resources/AppIcon.icns from {SOURCE}")

#!/usr/bin/env python3
"""Generate an iOS AppIcon asset catalog from desktop/icons/icon.svg geometry.

Pure-Pillow redraw of the same logo (rounded rect + W polyline) so the
repository does not need an SVG rasterizer at build time.
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw

SIZE = 1024
BG = (0x16, 0x73, 0x62, 255)
FG = (255, 255, 255, 255)


def draw_icon(size: int) -> Image.Image:
    # Source art lives in a 512x512 viewBox; scale it to fill the target canvas.
    # Render at 4x then downsample for clean anti-aliased strokes.
    view = 512.0
    scale = (size / view) * 4
    s = int(round(size * 4))
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8 * scale, 8 * scale, 504 * scale, 504 * scale], radius=int(round(112 * scale)), fill=BG)
    pts = [(102, 148), (166, 362), (256, 238), (346, 362), (410, 148)]
    d.line([(x * scale, y * scale) for x, y in pts], fill=FG, width=max(1, int(round(46 * scale))), joint="curve")
    r = 23 * scale
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x * scale - r, y * scale - r, x * scale + r, y * scale + r], fill=FG)
    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "WB2API/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(out, exist_ok=True)
    icon = draw_icon(SIZE)
    icon.save(os.path.join(out, "AppIcon-1024.png"))
    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(out, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(contents, fh, indent=2)
        fh.write("\n")
    accent = os.path.join(os.path.dirname(out), "AccentColor.colorset")
    os.makedirs(accent, exist_ok=True)
    with open(os.path.join(accent, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "colors": [
                    {
                        "color": {
                            "color-space": "srgb",
                            "components": {"alpha": "1.000", "blue": "0.384", "green": "0.451", "red": "0.086"},
                        },
                        "idiom": "universal",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            fh,
            indent=2,
        )
        fh.write("\n")
    print(f"wrote {out}/AppIcon-1024.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

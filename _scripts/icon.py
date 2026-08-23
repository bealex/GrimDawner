# Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.
"""Builds the app icon set from the artwork in Assets/.

Two drawings go in: the detailed one, and a simpler one that survives being shrunk. Which sizes take
the simple drawing is the only choice here — the Dock asks for 128 pixels at a standard tile on a
Retina display and up to 256 at a large one, so a threshold of 256 puts the simple drawing in the Dock
while Finder's previews and the app switcher keep the detail.
"""

import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw

CANVAS, ART, RADIUS = 1024, 824, 180
SIZES = (16, 32, 128, 256, 512)
ROOT = pathlib.Path(__file__).resolve().parent.parent


def tile(path):
    """The artwork trimmed of its black margin, inset on the canvas and masked to the rounded square."""
    art = Image.open(path).convert("RGBA")
    lit = np.array(art.convert("L")) > 18
    rows, columns = np.where(lit.any(axis=1))[0], np.where(lit.any(axis=0))[0]
    pad = 8
    art = art.crop((
        max(columns.min() - pad, 0), max(rows.min() - pad, 0),
        min(columns.max() + pad, art.width), min(rows.max() + pad, art.height),
    ))

    side = max(art.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 255))
    square.paste(art, ((side - art.width) // 2, (side - art.height) // 2), art)

    art = square.resize((ART, ART), Image.LANCZOS)
    shape = Image.new("L", (ART, ART), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, ART - 1, ART - 1], radius=RADIUS, fill=255)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, ((CANVAS - ART) // 2, (CANVAS - ART) // 2), shape)
    return canvas


def main(threshold):
    detailed = tile(ROOT / "Assets/image.png")
    simple = tile(ROOT / "Assets/image-low.png")
    out = ROOT / "Code/App/Assets.xcassets/AppIcon.appiconset"

    images = []
    for size in SIZES:
        for scale in (1, 2):
            pixels = size * scale
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            source = simple if pixels <= threshold else detailed
            source.resize((pixels, pixels), Image.LANCZOS).save(out / name)
            images.append({"size": f"{size}x{size}", "idiom": "mac", "filename": name, "scale": f"{scale}x"})

    (out / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2)
    )
    print(f"icon ✅ simple drawing up to {threshold}px, detailed above")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 256)

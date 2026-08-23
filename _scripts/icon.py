# Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.
"""Builds the app icon set from the artwork in Assets/.

Every size is drawn by hand: `image-low-<pixels>.png` is the simple drawing that survives being small,
`image-high-<pixels>.png` the detailed one. Each file goes into the icon set at its own resolution, so
nothing is resampled; all this adds is the rounded-square mask macOS expects.
"""

import json
import pathlib
import sys

from PIL import Image, ImageDraw

SIZES = (16, 32, 128, 256, 512)
CORNER = 0.22
ROOT = pathlib.Path(__file__).resolve().parent.parent


def tile(pixels, threshold):
    """The drawing authored at this size, masked to the rounded square."""
    kind = "low" if pixels <= threshold else "high"
    # The full-size drawing carries no size in its name, and is the one every larger tile comes from.
    art = next(
        (path for path in (ROOT / f"Assets/image-{kind}-{pixels}.png", ROOT / f"Assets/image-{kind}.png")
         if path.exists()),
        None,
    )
    if art is None:
        raise SystemExit(f"no {kind} artwork at {pixels}px")

    image = Image.open(art).convert("RGBA").resize((pixels, pixels), Image.LANCZOS)
    # The mask is drawn four times over and shrunk, since a 16px corner drawn directly is a staircase.
    shape = Image.new("L", (pixels * 4, pixels * 4), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [0, 0, pixels * 4 - 1, pixels * 4 - 1], radius=round(pixels * 4 * CORNER), fill=255
    )
    masked = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
    masked.paste(image, (0, 0), shape.resize((pixels, pixels), Image.LANCZOS))
    return masked


def main(threshold):
    out = ROOT / "Code/App/Assets.xcassets/AppIcon.appiconset"
    images = []

    for size in SIZES:
        for scale in (1, 2):
            pixels = size * scale
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            tile(pixels, threshold).save(out / name)
            images.append({"size": f"{size}x{size}", "idiom": "mac", "filename": name, "scale": f"{scale}x"})

    (out / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2)
    )
    print(f"icon ✅ simple drawing up to {threshold}px, detailed above")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 256)

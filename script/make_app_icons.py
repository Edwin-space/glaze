#!/usr/bin/env python3
"""Rebuild the app icons for macOS and iOS from one master image.

The master that shipped had the area outside its rounded square painted
#F5F5F5 rather than left transparent, so the Mac icon carried a light grey
block behind it in the Dock. This lifts the artwork off that background and
writes what each platform wants:

  macOS — the rounded shape with transparency around it, at every size
  iOS   — a full-bleed square with no alpha; iOS applies the mask itself

The outside is found by flooding in from the corners rather than by colour
alone: the amber mark is closer to white than the shape's own edge is, so a
plain colour test would eat holes in the artwork.
"""
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "Sources/GlazeMac/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
MAC_SET = ROOT / "Sources/GlazeMac/Resources/Assets.xcassets/AppIcon.appiconset"
IOS_SET = ROOT / "Sources/GlazeiOS/Resources/Assets.xcassets/AppIcon.appiconset"

PAINTED_BACKGROUND = (245, 245, 245)
#: The shape's own edge colour, which every corner blend runs towards.
SHAPE_EDGE = (34, 32, 24)


def _distance(colour, other):
    return max(abs(a - b) for a, b in zip(colour, other))


def lift_from_background(image: Image.Image) -> Image.Image:
    source = image.convert("RGB")
    width, height = source.size
    pixels = source.load()

    full_blend = _distance(SHAPE_EDGE, PAINTED_BACKGROUND)
    # The edge is not one pixel wide — the shape fades into the grey over six or
    # eight of them — so the flood runs in from the corners across the whole ramp
    # and stops only where the pixel is as dark as the shape itself. The amber
    # mark sits inside a ring of that dark, so the flood can never reach it.
    ramp_limit = full_blend - 3

    outside = bytearray(width * height)
    queue = deque([(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)])
    while queue:
        x, y = queue.popleft()
        if not (0 <= x < width and 0 <= y < height) or outside[y * width + x]:
            continue
        if _distance(pixels[x, y], PAINTED_BACKGROUND) >= ramp_limit:
            continue
        outside[y * width + x] = 1
        queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))

    out = Image.new("RGBA", (width, height))
    target = out.load()

    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            if not outside[y * width + x]:
                target[x, y] = (r, g, b, 255)
                continue

            # Somewhere on the ramp: how much of this pixel the shape covers,
            # then undo the blend so the edge keeps its own colour rather than a
            # grey tint.
            coverage = min(_distance((r, g, b), PAINTED_BACKGROUND) / full_blend, 1.0)
            if coverage <= 0:
                target[x, y] = (0, 0, 0, 0)
                continue
            unblended = tuple(
                min(255, max(0, round((c - bg * (1 - coverage)) / coverage)))
                for c, bg in zip((r, g, b), PAINTED_BACKGROUND)
            )
            target[x, y] = (*unblended, round(coverage * 255))
    return out


def fill_to_the_edges(shape: Image.Image) -> Image.Image:
    """Carry each row's outermost solid colour out to the canvas edge.

    iOS rounds the corners itself and refuses an alpha channel, so the icon has
    to be a full square. Extending the background outwards keeps the gradient
    continuous where a flat fill would show a seam.
    """
    width, height = shape.size
    pixels = shape.load()
    out = Image.new("RGB", (width, height))
    target = out.load()

    for y in range(height):
        solid = [x for x in range(width) if pixels[x, y][3] == 255]
        if not solid:
            continue
        left, right = solid[0], solid[-1]
        for x in range(width):
            if x < left:
                r, g, b = pixels[left, y][:3]
            elif x > right:
                r, g, b = pixels[right, y][:3]
            else:
                r, g, b, _ = pixels[x, y]
            target[x, y] = (r, g, b)
    return out


def main() -> None:
    shape = lift_from_background(Image.open(MASTER))

    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            side = size * scale
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            shape.resize((side, side), Image.LANCZOS).save(MAC_SET / name)
    print(f"macOS: 10 sizes → {MAC_SET.relative_to(ROOT)}")

    IOS_SET.mkdir(parents=True, exist_ok=True)
    fill_to_the_edges(shape).save(IOS_SET / "icon_1024.png")
    print(f"iOS: icon_1024.png → {IOS_SET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

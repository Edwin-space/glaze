#!/usr/bin/env python3
"""Rebuild every platform's app icons from one master image.

The master that shipped had the area outside its rounded square painted
#F5F5F5 rather than left transparent, so the Mac icon carried a light grey
block behind it in the Dock. This lifts the artwork off that background and
writes what each platform wants:

  macOS — the rounded shape with transparency around it, at every size
  iOS   — a full-bleed square with no alpha; iOS applies the mask itself
  tvOS  — layered art, 400x240 and wider, built from a background and the mark

It also writes the mark on its own for the iPhone and iPad launch screen, which
has to be a static image: there is no code running yet when it is shown.

The outside is found by flooding in from the corners rather than by colour
alone: the amber mark is closer to white than the shape's own edge is, so a
plain colour test would eat holes in the artwork.

The tvOS assets used to be this square icon pasted into the middle of a wide
frame with the remaining space filled in — the square's edges were plainly
visible on the television, on the home screen and in the top shelf. Worse, the
two parallax layers held the identical file, so the layering did nothing. They
are composed here instead: the background fills the frame, and the mark sits on
the front layer by itself, which is what gives tvOS something to separate when
the icon is focused.
"""
import json
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "Sources/GlazeMac/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
MAC_SET = ROOT / "Sources/GlazeMac/Resources/Assets.xcassets/AppIcon.appiconset"
IOS_SET = ROOT / "Sources/GlazeiOS/Resources/Assets.xcassets/AppIcon.appiconset"
TV_BRAND = ROOT / "Sources/GlazeTV/Resources/Assets.xcassets/AppIcon.brandassets"
IOS_ASSETS = ROOT / "Sources/GlazeiOS/Resources/Assets.xcassets"

PAINTED_BACKGROUND = (245, 245, 245)
#: The shape's own edge colour, which every corner blend runs towards.
SHAPE_EDGE = (34, 32, 24)
#: The ground the mark sits on, sampled from the master's corners. tvOS art is
#: built from these rather than by cropping the square, so nothing has an edge.
GROUND_NEAR = (31, 29, 23)
GROUND_FAR = (10, 10, 13)
#: The mark is the only bright thing inside the shape: its ground reads about 28,
#: the unlit arc about 56, the amber about 240.
MARK_FLOOR = 34
MARK_CEILING = 52


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



def isolate_mark(shape: Image.Image) -> Image.Image:
    """The mark alone, on transparency, cropped to what it covers.

    Inside the shape the ground is very dark and the mark — both its unlit arc
    and the amber — is much brighter, so brightness separates them cleanly. The
    ramp between the two becomes the alpha, which keeps the curve smooth.
    """
    width, height = shape.size
    pixels = shape.load()
    out = Image.new("RGBA", (width, height))
    target = out.load()

    span = MARK_CEILING - MARK_FLOOR
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                target[x, y] = (0, 0, 0, 0)
                continue
            brightness = max(r, g, b)
            coverage = min(max((brightness - MARK_FLOOR) / span, 0.0), 1.0)
            target[x, y] = (r, g, b, round(coverage * a))

    return out.crop(out.getbbox())


def ground(size: tuple[int, int], glow: float = 0.0) -> Image.Image:
    """The diagonal ground the mark sits on, at any shape of canvas.

    `glow` lifts the middle a little. The unlit half of the mark is only a shade
    brighter than this ground, and on a television across a room it disappears
    into it without something behind it to sit against.
    """
    width, height = size
    out = Image.new("RGB", size)
    target = out.load()
    longest = max(width - 1, 1) + max(height - 1, 1)
    centre_x, centre_y = (width - 1) / 2, (height - 1) / 2
    reach = max(min(width, height) / 2, 1)

    for y in range(height):
        for x in range(width):
            t = (x + y) / longest
            base = [near + (far - near) * t for near, far in zip(GROUND_NEAR, GROUND_FAR)]
            if glow > 0:
                distance = ((x - centre_x) ** 2 + (y - centre_y) ** 2) ** 0.5 / reach
                lift = glow * max(1.0 - distance, 0.0) ** 2
                base = [channel + lift for channel in base]
            target[x, y] = tuple(min(255, max(0, round(channel))) for channel in base)
    return out


def _placed_mark(mark: Image.Image, size: tuple[int, int], height_fraction: float) -> Image.Image:
    """The mark, on transparency, centred in a canvas of `size`."""
    width, height = size
    target_height = round(height * height_fraction)
    scale = target_height / mark.height
    scaled = mark.resize((max(round(mark.width * scale), 1), target_height), Image.LANCZOS)

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(scaled, ((width - scaled.width) // 2, (height - scaled.height) // 2), scaled)
    return layer


def _write_imageset(directory: Path, entries: list[tuple[str, Image.Image]], idiom: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    images = []
    for name, image in entries:
        image.save(directory / name)
        scale = "2x" if "@2x" in name else "1x"
        images.append({"filename": name, "idiom": idiom, "scale": scale})
    (directory / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )


def _write_single_scale_imageset(directory: Path, name: str, image: Image.Image, idiom: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    image.save(directory / name)
    (directory / "Contents.json").write_text(
        json.dumps(
            {"images": [{"filename": name, "idiom": idiom}], "info": {"author": "xcode", "version": 1}},
            indent=2,
        )
        + "\n"
    )


def write_tv_assets(mark: Image.Image) -> None:
    """The layered icon and top shelf art tvOS asks for.

    Every layer covers the whole frame. The back holds the ground, the front
    holds only the mark, so the television has two planes to move against each
    other when the icon takes focus.
    """
    def stack(directory: Path, sizes: list[tuple[str, tuple[int, int]]], fraction: float, idiom: str) -> None:
        for layer, produce in (("Back", lambda s: ground(s, glow=26).convert("RGBA")),
                               ("Front", lambda s: _placed_mark(mark, s, fraction))):
            content = directory / f"{layer}.imagestacklayer" / "Content.imageset"
            entries = [(name, produce(size)) for name, size in sizes]
            if len(entries) == 1:
                _write_single_scale_imageset(content, entries[0][0], entries[0][1], idiom)
            else:
                _write_imageset(content, entries, idiom)
            (directory / f"{layer}.imagestacklayer" / "Contents.json").write_text(
                json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
            )
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "Contents.json").write_text(
            json.dumps(
                {"layers": [{"filename": "Front.imagestacklayer"}, {"filename": "Back.imagestacklayer"}],
                 "info": {"author": "xcode", "version": 1}},
                indent=2,
            )
            + "\n"
        )

    stack(
        TV_BRAND / "App Icon.imagestack",
        [("glaze-tv-app-icon.png", (400, 240)), ("glaze-tv-app-icon@2x.png", (800, 480))],
        0.70,
        "tv",
    )
    # The App Store icon is delivered at one size and must not be layered for
    # parallax, but the same composition keeps the two looking like one icon.
    stack(
        TV_BRAND / "App Icon - App Store.imagestack",
        [("glaze-tv-app-store-icon.png", (1280, 768))],
        0.70,
        "tv-marketing",
    )

    for name, sizes in (
        ("Top Shelf Image", [("glaze-top-shelf.png", (1920, 720)), ("glaze-top-shelf@2x.png", (3840, 1440))]),
        ("Top Shelf Image Wide", [("glaze-top-shelf-wide.png", (2320, 720)), ("glaze-top-shelf-wide@2x.png", (4640, 1440))]),
    ):
        entries = []
        for filename, size in sizes:
            banner = ground(size, glow=22).convert("RGBA")
            banner.alpha_composite(_placed_mark(mark, size, 0.46))
            entries.append((filename, banner.convert("RGB")))
        _write_imageset(TV_BRAND / f"{name}.imageset", entries, "tv")

    print(f"tvOS: layered icon and top shelf art → {TV_BRAND.relative_to(ROOT)}")



def write_launch_art(mark: Image.Image) -> None:
    """The mark for the launch screen, and the ground it sits on.

    The launch screen is a static image shown before any of the app is running,
    so it cannot draw the library or a spinner. Matching the app's own ground
    means the first frame of the app replaces it without a flash.
    """
    logo = IOS_ASSETS / "LaunchLogo.imageset"
    logo.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        side = 132 * scale
        height = round(mark.height * side / mark.width)
        name = f"launch-logo{'' if scale == 1 else f'@{scale}x'}.png"
        mark.resize((side, height), Image.LANCZOS).save(logo / name)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    (logo / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    colour = IOS_ASSETS / "LaunchBackground.colorset"
    colour.mkdir(parents=True, exist_ok=True)
    components = {
        "red": f"0x{GROUND_NEAR[0]:02X}",
        "green": f"0x{GROUND_NEAR[1]:02X}",
        "blue": f"0x{GROUND_NEAR[2]:02X}",
        "alpha": "1.000",
    }
    (colour / "Contents.json").write_text(
        json.dumps(
            {
                "colors": [
                    {
                        "color": {"color-space": "srgb", "components": components},
                        "idiom": "universal",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )
    print(f"iOS: launch logo and background → {IOS_ASSETS.relative_to(ROOT)}")


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

    mark = isolate_mark(shape)
    write_tv_assets(mark)
    write_launch_art(mark)


if __name__ == "__main__":
    main()

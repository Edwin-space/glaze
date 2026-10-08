"""Lays App Store captions over screenshots taken from the running app.

The screenshots come from `StoreScreenshots` in the UI test target, so the picture
is the product rather than a mock-up of it. Sizes are whatever the simulator
produced — 1320x2868 for the 6.9-inch iPhone, 2064x2752 for the 13-inch iPad —
and nothing here resamples them upward.

The film on screen is Sintel, (c) Blender Foundation, CC BY 3.0. The licence asks
for attribution wherever the work is shown, and an App Store listing is shown very
widely, so the credit is drawn into every image that contains a frame of it.

    python3 Tools/make_store_images.py <screenshot dir> <output dir>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GROUND = (14, 14, 16)
AMBER = (232, 150, 61)
DIM = (168, 168, 174)
FAINT = (120, 120, 126)

KO = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
CREDIT = "Sintel © Blender Foundation · CC BY 3.0 · durian.blender.org"

# headline, sub-headline, whether the shot contains a frame of the film
PLAN = [
    ("01-library", "내 영상, 내 기기에서", "계정도 구독도 없습니다. 폴더에 넣으면 그대로 보입니다.", False),
    ("02-player", "MKV도 그대로 재생합니다", "멈춘 자리를 기억하고, 다음 화로 이어집니다.", True),
    # The subtitle sheet is missing on purpose. Two attempts to open it from the
    # test — by label and by position — left the player on screen instead, and a
    # caption about subtitles over a picture of the player is a lie about the
    # product. It goes back in when the test can actually open the sheet.
    ("04-scrub-1", "찾는 장면이 보입니다", "재생 막대를 끄는 동안 그 지점의 장면을 미리 보여줍니다.", True),
]


def font(size, index=9):
    return ImageFont.truetype(KO, size, index=index)


def wrap(draw, text, fnt, width):
    out, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            if line:
                out.append(line)
            line = word
    if line:
        out.append(line)
    return out


def compose(shot_path, headline, sub, credited, out_path):
    shot = Image.open(shot_path).convert("RGB")
    width, height = shot.size
    canvas = Image.new("RGB", (width, height), GROUND)
    draw = ImageDraw.Draw(canvas)

    # Everything scales off the frame's width, so one plan serves a phone and a
    # tablet without a second set of numbers.
    unit = width / 1320
    margin = round(96 * unit)
    title_font = font(round(86 * unit), 9)
    sub_font = font(round(48 * unit), 3)
    credit_font = font(round(30 * unit), 3)

    y = round(150 * unit)
    for line in wrap(draw, headline, title_font, width - margin * 2):
        draw.text((margin, y), line, font=title_font, fill=(255, 255, 255))
        y += round(104 * unit)
    y += round(14 * unit)
    for line in wrap(draw, sub, sub_font, width - margin * 2):
        draw.text((margin, y), line, font=sub_font, fill=DIM)
        y += round(64 * unit)

    top = y + round(90 * unit)
    bottom_reserve = round((120 if credited else 60) * unit)
    inner_width = width - margin * 2
    scaled_height = round(shot.height * inner_width / shot.width)
    shot = shot.resize((inner_width, scaled_height), Image.LANCZOS)

    # The screen is cropped rather than shrunk: a whole device drawn small reads as
    # a thumbnail, and what the caption points at is near the top anyway.
    visible = min(scaled_height, height - top - bottom_reserve)
    shot = shot.crop((0, 0, inner_width, visible))

    radius = round(64 * unit)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner_width - 1, visible - 1], radius=radius, fill=255)
    canvas.paste(shot, (margin, top), mask)

    edge = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [margin, top, margin + inner_width - 1, top + visible - 1],
        radius=radius, outline=AMBER + (70,), width=max(2, round(3 * unit))
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), edge).convert("RGB")

    if credited:
        draw = ImageDraw.Draw(canvas)
        draw.text(
            (margin, top + visible + round(28 * unit)),
            CREDIT, font=credit_font, fill=FAINT
        )

    canvas.save(out_path)
    return out_path


def main():
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    made = 0
    for name, headline, sub, credited in PLAN:
        shot = source / f"{name}.png"
        if not shot.exists():
            print(f"skipped {name}: not taken")
            continue
        print(compose(shot, headline, sub, credited, destination / f"{name}.png"))
        made += 1
    if made == 0:
        raise SystemExit("no screenshots found — run the StoreScreenshots test first")


if __name__ == "__main__":
    main()

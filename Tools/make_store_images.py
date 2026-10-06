"""Builds App Store listing images from real screenshots.

1320x2868 is the 6.9" iPhone size App Store Connect asks for, and it is what the
screenshots already are: the picture inside is not resampled up from a smaller
phone. The caption is the only thing added, and it says what the screen does
rather than selling it.
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1320, 2868
GROUND = (14, 14, 16)
AMBER = (232, 150, 61)
DIM = (168, 168, 174)

KO_BOLD = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

def font(size, index=9):
    return ImageFont.truetype(KO_BOLD, size, index=index)

def wrap(draw, text, fnt, max_width):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= max_width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines

def compose(shot_path, headline, sub, out_path):
    canvas = Image.new("RGB", (W, H), GROUND)
    draw = ImageDraw.Draw(canvas)

    title_font = font(86, 9)
    sub_font = font(48, 3)

    margin = 96
    y = 150
    for line in wrap(draw, headline, title_font, W - margin * 2):
        draw.text((margin, y), line, font=title_font, fill=(255, 255, 255))
        y += 104
    y += 14
    for line in wrap(draw, sub, sub_font, W - margin * 2):
        draw.text((margin, y), line, font=sub_font, fill=DIM)
        y += 64

    top = y + 90
    shot = Image.open(shot_path).convert("RGB")
    width = W - margin * 2
    height = round(shot.height * width / shot.width)
    shot = shot.resize((width, height), Image.LANCZOS)

    # The screen is cropped at the bottom rather than shrunk: a whole phone drawn
    # small reads as a thumbnail, and the part being pointed at is at the top.
    visible = min(height, H - top - 60)
    shot = shot.crop((0, 0, width, visible))

    rounded = Image.new("L", shot.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, width - 1, visible - 1], radius=64, fill=255)
    canvas.paste(shot, (margin, top), rounded)

    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [margin, top, margin + width - 1, top + visible - 1],
        radius=64, outline=AMBER + (70,), width=3
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), edge).convert("RGB")
    canvas.save(out_path)
    return out_path

if __name__ == "__main__":
    import sys
    base, out = sys.argv[1], sys.argv[2]
    plan = [
        ("04-settings.png", "내 영상, 내 기기에서", "계정도 구독도 없습니다. 폴더에 넣으면 그대로 보입니다.", "01-library.png"),
        ("02-player.png", "보던 그대로 이어서", "MKV도 그대로 재생합니다. 멈춘 자리를 기억합니다.", "02-play.png"),
        ("03-scrub.png", "찾는 장면이 보입니다", "재생 막대를 끄는 동안 그 지점의 장면을 미리 보여줍니다.", "03-scrub.png"),
    ]
    for src, head, sub, name in plan:
        print(compose(f"{base}/{src}", head, sub, f"{out}/{name}"))

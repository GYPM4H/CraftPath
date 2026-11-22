"""CurseForge gallery images: a screenshot on a dark 16:9 card with a caption.

Usage: python tools/make_gallery.py <main_window.png> <tracker.png>
Writes screenshots/gallery-1-planner.png and screenshots/gallery-2-tracker.png (1600x900).
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "screenshots")
W, H = 1600, 900
AMBER = (242, 165, 65)
TEXT = (232, 230, 225)
MUTED = (160, 164, 172)
FONTS = r"C:\Windows\Fonts"


def font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONTS, name), size)
    except OSError:
        return ImageFont.load_default()


def background():
    bg = Image.new("RGB", (W, H), (14, 16, 21))
    px = bg.load()
    # soft amber glow behind the screenshot (right), darker towards the left
    for y in range(H):
        for x in range(W):
            dx, dy = (x - 1150) / 900, (y - 450) / 700
            g = max(0.0, 1 - (dx * dx + dy * dy)) ** 2
            px[x, y] = (int(14 + 34 * g), int(16 + 22 * g), int(21 + 8 * g))
    return bg


def wrap(draw, text, f, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        test = (line + " " + w).strip()
        if draw.textlength(test, font=f) <= width:
            line = test
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def card(shot, scale, title, points, out_name):
    img = background()
    if scale != 1:
        shot = shot.resize((shot.width * scale, shot.height * scale), Image.NEAREST)
    sx = W - shot.width - 80
    sy = (H - shot.height) // 2
    # drop shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rectangle([sx + 6, sy + 14, sx + shot.width + 6, sy + shot.height + 14], fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(18))
    img = Image.alpha_composite(img.convert("RGBA"), sh)
    img.alpha_composite(shot.convert("RGBA"), (sx, sy))

    d = ImageDraw.Draw(img)
    left, maxw = 80, sx - 80 - 70
    # logo + name
    icon_path = os.path.join(ROOT, "Media", "Icon.tga")
    y = 150
    if os.path.exists(icon_path):
        icon = Image.open(icon_path).convert("RGBA").resize((64, 64), Image.LANCZOS)
        img.alpha_composite(icon, (left, y - 4))
    d.text((left + 80, y + 2), "CraftPath", font=font("segoeuib.ttf", 40), fill=TEXT)
    d.text((left + 82, y + 50), "WoW Forever profession leveling planner", font=font("segoeui.ttf", 18), fill=MUTED)
    y += 130
    tf = font("segoeuib.ttf", 34)
    for line in wrap(d, title, tf, maxw):
        d.text((left, y), line, font=tf, fill=AMBER)
        y += 46
    y += 18
    bf = font("segoeui.ttf", 22)
    for p in points:
        lines = wrap(d, p, bf, maxw - 28)
        d.ellipse([left + 2, y + 11, left + 12, y + 21], fill=AMBER)
        for line in lines:
            d.text((left + 28, y), line, font=bf, fill=TEXT)
            y += 32
        y += 12

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, out_name)
    img.convert("RGB").save(path, optimize=True)
    print(path, os.path.getsize(path), "bytes")


def main():
    main_shot, tracker_shot = Image.open(sys.argv[1]), Image.open(sys.argv[2])
    card(main_shot, 1, "The cheapest way to level, from live AH prices", [
        "Plans every step from your skill to your target",
        "Knows which recipes you have, and where to learn the rest",
        "Click a dot to set a waypoint to the trainer",
        "Cost, materials and crafting time at a glance",
    ], "gallery-1-planner.png")
    card(tracker_shot, 2, "Track your progress while you craft", [
        "Current craft, skill-up chance and attempts left",
        "Missing materials, counting bags and bank",
        "Craft or craft-all with one click",
        "What to craft next, and when to train",
    ], "gallery-2-tracker.png")


if __name__ == "__main__":
    main()

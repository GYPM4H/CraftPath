"""Draws the CraftPath icon: ascending amber steps with a rising arrow, in a
dark round badge with an amber ring. Writes CraftPath/Media/Icon.tga (128x128,
32-bit, what WoW loads) and tools/icon_preview.png."""
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media")
N = 1024            # draw big, scale down for smooth edges
C = N / 2
AMBER = (242, 165, 65)
AMBER_HI = (255, 214, 140)
AMBER_LO = (196, 110, 28)


def vgrad(size, top, bottom, y0=0, y1=None):
    """Vertical gradient image (RGBA) from top to bottom colour between y0..y1."""
    y1 = y1 or size
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = min(1, max(0, (y - y0) / max(1, y1 - y0)))
        col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(size):
            px[x, y] = col
    return img


def radial(size, inner, outer, cx, cy, r):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = min(1, math.hypot(x - cx, y - cy) / r)
            t = t ** 1.4
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3)) + (255,)
    return img


def mask(draw_fn):
    m = Image.new("L", (N, N), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def paste(base, fill, m):
    base.alpha_composite(Image.composite(fill, Image.new("RGBA", (N, N), (0, 0, 0, 0)), m))


def main():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    R = N * 0.47

    # soft drop shadow behind the badge
    sh = mask(lambda d: d.ellipse([C - R, C - R + 14, C + R, C + R + 14], fill=150)).filter(ImageFilter.GaussianBlur(18))
    paste(img, Image.new("RGBA", (N, N), (0, 0, 0, 255)), sh)

    # amber ring (gradient), then dark face
    paste(img, vgrad(N, AMBER_HI, AMBER_LO, int(C - R), int(C + R)),
          mask(lambda d: d.ellipse([C - R, C - R, C + R, C + R], fill=255)))
    r2 = R * 0.88
    paste(img, (radial(N // 4, (48, 54, 66), (16, 18, 24), N // 8 - 10, N // 8 - 22, N // 8 + 30)).resize((N, N), Image.BICUBIC),
          mask(lambda d: d.ellipse([C - r2, C - r2, C + r2, C + r2], fill=255)))
    # thin inner highlight on the ring edge
    ring = mask(lambda d: d.ellipse([C - r2 - 6, C - r2 - 6, C + r2 + 6, C + r2 + 6], outline=255, width=6))
    paste(img, Image.new("RGBA", (N, N), (90, 52, 10, 255)), ring)

    # three ascending steps
    base_y = C + r2 * 0.52
    w, gap = r2 * 0.34, r2 * 0.07
    x0 = C - (3 * w + 2 * gap) / 2
    heights = [0.30, 0.58, 0.88]
    steps = mask(lambda d: [d.rounded_rectangle(
        [x0 + i * (w + gap), base_y - r2 * h, x0 + i * (w + gap) + w, base_y],
        radius=int(w * 0.16), fill=255) for i, h in enumerate(heights)])
    # step shadow
    paste(img, Image.new("RGBA", (N, N), (0, 0, 0, 255)),
          ImageChops.offset(steps, 0, 12).filter(ImageFilter.GaussianBlur(10)).point(lambda v: v * 0.7))
    paste(img, vgrad(N, AMBER_HI, AMBER_LO, int(base_y - r2 * 0.88), int(base_y)), steps)
    # lit top edge of each step
    tops = mask(lambda d: [d.rounded_rectangle(
        [x0 + i * (w + gap) + 8, base_y - r2 * h + 6, x0 + i * (w + gap) + w - 8, base_y - r2 * h + 22],
        radius=8, fill=255) for i, h in enumerate(heights)])
    paste(img, Image.new("RGBA", (N, N), (255, 240, 205, 255)), tops)

    # rising arrow over the steps
    ax0, ay0 = x0 - r2 * 0.02, base_y - r2 * 0.50
    ax1, ay1 = x0 + 3 * w + 2 * gap - r2 * 0.10, C - r2 * 0.62
    ang = math.atan2(ay1 - ay0, ax1 - ax0)
    ux, uy = math.cos(ang), math.sin(ang)
    nx, ny = -uy, ux
    th, head, hw = r2 * 0.075, r2 * 0.30, r2 * 0.23
    bx, by = ax1 - ux * head, ay1 - uy * head
    shaft = [(ax0 + nx * th, ay0 + ny * th), (bx + nx * th, by + ny * th),
             (bx - nx * th, by - ny * th), (ax0 - nx * th, ay0 - ny * th)]
    tip = [(ax1 + ux * 6, ay1 + uy * 6), (bx + nx * hw, by + ny * hw), (bx - nx * hw, by - ny * hw)]
    arrow = mask(lambda d: (d.polygon(shaft, fill=255), d.polygon(tip, fill=255),
                            d.ellipse([ax0 - th, ay0 - th, ax0 + th, ay0 + th], fill=255)))
    outline = arrow.filter(ImageFilter.MaxFilter(25))
    paste(img, Image.new("RGBA", (N, N), (14, 16, 22, 255)), outline)
    paste(img, vgrad(N, (255, 255, 255), (232, 226, 210), int(ay1), int(ay0)), arrow)

    # small sparkle at the arrow tip
    sx, sy, s = ax1 + ux * r2 * 0.02 + r2 * 0.10, ay1 - r2 * 0.12, r2 * 0.09
    spark = mask(lambda d: d.polygon([(sx, sy - s), (sx + s * 0.25, sy - s * 0.25), (sx + s, sy),
                                       (sx + s * 0.25, sy + s * 0.25), (sx, sy + s), (sx - s * 0.25, sy + s * 0.25),
                                       (sx - s, sy), (sx - s * 0.25, sy - s * 0.25)], fill=255))
    paste(img, Image.new("RGBA", (N, N), AMBER_HI + (255,)), spark)

    small = img.resize((128, 128), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    small.save(os.path.join(OUT, "Icon.tga"), compression=None)   # uncompressed 32-bit TGA
    small.resize((256, 256), Image.NEAREST).save(os.path.join(HERE, "icon_preview.png"))
    # what it looks like at minimap size
    prev = Image.new("RGBA", (420, 140), (30, 30, 34, 255))
    prev.alpha_composite(small, (8, 6))
    prev.alpha_composite(img.resize((64, 64), Image.LANCZOS), (170, 38))
    prev.alpha_composite(img.resize((32, 32), Image.LANCZOS), (270, 54))
    prev.alpha_composite(img.resize((20, 20), Image.LANCZOS), (340, 60))
    prev.save(os.path.join(HERE, "icon_sizes.png"))
    logo = img.resize((400, 400), Image.LANCZOS)
    logo.save(os.path.join(HERE, "curseforge_logo.png"), optimize=True)
    print("ok")


if __name__ == "__main__":
    main()

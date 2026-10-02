#!/usr/bin/env python3
"""Generate Shiori's own icon: a bookmark ribbon (栞, shiori) under a
magnifying glass that enlarges it, in Tokyo Night colours.

- AppIcon: navy, blue ribbon, gold lens (the default).
- AppIcon-Light: the Tokyo Night Day version.
- IconPreview-Default / IconPreview-Light: the Settings picker's previews.
- assets/icon-*.png: the Safari extension's icons. 48 and up are the tile;
  the toolbar's 16 and 32 are the ribbon and lens alone, on transparent
  (Safari draws toolbar buttons small and sometimes tints them, where a
  tile would turn into a blob), plus grey versions for skipped pages.
- assets/web-icon-*.png: the web app's and search page's icons, a rounded
  tile as the Machiya rooms draw theirs (corner radius 112 of 512), and web-maskable-512.png, the whole square with the
  mark shrunk into Android's safe zone (a circle of 80% of the width), so
  its mask never clips the lens.

Needs Pillow (python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "Shiori/Assets.xcassets")
ASSETS = os.path.join(ROOT, "assets")
S = 4096  # drawn large, then shrunk for smooth edges

# `tint`: the glass's sheen over what it enlarges. `glass`: its fill where
# nothing is enlarged (the toolbar glyph).
NIGHT = dict(bg=(26, 27, 38), ribbon=(122, 162, 247), ring=(224, 175, 104), glass=(58, 59, 72),
             tint=(255, 255, 255, 28))
DAY = dict(bg=(225, 226, 231), ribbon=(46, 125, 233), ring=(140, 108, 62), glass=(208, 213, 227),
           tint=(255, 255, 255, 60))

RIBBON = (0.22, 0.0, 0.3, 0.72, 0.13)  # x, top, width, bottom, notch depth
LENS = (0.53, 0.58, 0.18)  # centre x, centre y, radius
RING, HANDLE, ZOOM = 0.05, 0.17, 1.4


def u(v):
    return int(v * S)


def ribbon_poly(x, top, w, bottom, notch):
    return [(u(x), u(top)), (u(x + w), u(top)), (u(x + w), u(bottom)),
            (u(x + w / 2), u(bottom - notch)), (u(x), u(bottom))]


def draw_mark(img, palette, magnify=True, shadow=True):
    """The ribbon, then the lens over its edge showing it enlarged."""
    poly = ribbon_poly(*RIBBON)
    if shadow:
        sh = Image.new("L", (S, S), 0)
        ImageDraw.Draw(sh).polygon([(x + u(0.012), y + u(0.012)) for x, y in poly], fill=90)
        sh = sh.filter(ImageFilter.GaussianBlur(u(0.02)))
        img.paste(Image.new("RGBA", (S, S), (0, 0, 0, 255)), (0, 0), sh)
    ImageDraw.Draw(img).polygon(poly, fill=palette["ribbon"] + (255,))

    cx, cy, r = LENS
    disc = Image.new("L", (u(2 * r), u(2 * r)), 0)
    ImageDraw.Draw(disc).ellipse([0, 0, disc.size[0] - 1, disc.size[1] - 1], fill=255)
    if magnify:
        box = (u(cx - r / ZOOM), u(cy - r / ZOOM), u(cx + r / ZOOM), u(cy + r / ZOOM))
        zoomed = img.crop(box).resize(disc.size, Image.LANCZOS)
        img.paste(zoomed, (u(cx - r), u(cy - r)), disc)
        tint = Image.new("RGBA", disc.size, palette["tint"])
        img.paste(tint, (u(cx - r), u(cy - r)), Image.composite(tint.split()[3], Image.new("L", disc.size, 0), disc))
    else:
        img.paste(Image.new("RGBA", disc.size, palette["glass"] + (255,)), (u(cx - r), u(cy - r)), disc)

    d = ImageDraw.Draw(img)
    ring = palette["ring"] + (255,)
    a = math.radians(45)
    hx0, hy0 = cx + r * math.cos(a), cy + r * math.sin(a)
    hx1, hy1 = hx0 + HANDLE * math.cos(a), hy0 + HANDLE * math.sin(a)
    d.line([(u(hx0), u(hy0)), (u(hx1), u(hy1))], fill=ring, width=u(RING * 1.5))
    d.ellipse([u(hx1 - RING * 0.75), u(hy1 - RING * 0.75), u(hx1 + RING * 0.75), u(hy1 + RING * 0.75)], fill=ring)
    d.ellipse([u(cx - r), u(cy - r), u(cx + r), u(cy + r)], outline=ring, width=u(RING))
    # A highlight on the glass.
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rr = r - RING * 1.4
    ImageDraw.Draw(gloss).arc([u(cx - rr), u(cy - rr), u(cx + rr), u(cy + rr)], 200, 260,
                              fill=(255, 255, 255, 150), width=u(0.022))
    img.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(u(0.003))))


def app_icon(palette):
    img = Image.new("RGBA", (S, S), palette["bg"] + (255,))
    draw_mark(img, palette)
    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


TILE_RADIUS = 112 / 512  # the rooms' tile corner (machiya icons/*.svg)
MASKABLE_SCALE = 0.62  # the mark's farthest points land at 36% of the width from the centre


def rounded(image, size):
    """The tile with rounded corners, on transparent."""
    big = image.resize((size * 4, size * 4), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big.width - 1, big.height - 1], radius=int(big.width * TILE_RADIUS), fill=255)
    big.putalpha(mask)
    return big.resize((size, size), Image.LANCZOS)


def maskable(image, palette, size=512):
    """The whole square in the background colour, the tile's mark shrunk
    into the safe zone (the tile's own background meets the canvas's)."""
    canvas = Image.new("RGB", (size, size), palette["bg"])
    inner = int(size * MASKABLE_SCALE)
    canvas.paste(image.resize((inner, inner), Image.LANCZOS), ((size - inner) // 2, (size - inner) // 2))
    return canvas


def toolbar_glyph(size, grey=False):
    """Ribbon and lens alone, filling the square, on transparent."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    palette = dict(NIGHT, glass=(0, 0, 0))
    draw_mark(img, palette, magnify=False, shadow=False)
    # The glass stays see-through at toolbar size.
    cx, cy, r = LENS
    hole = Image.new("L", (S, S), 255)
    rr = r - RING / 2
    ImageDraw.Draw(hole).ellipse([u(cx - rr), u(cy - rr), u(cx + rr), u(cy + rr)], fill=0)
    alpha = Image.eval(img.split()[3], lambda v: v)
    img.putalpha(Image.composite(alpha, Image.new("L", (S, S), 0), hole))
    # Trim to the mark and centre it with a little margin.
    box = img.getbbox()
    mark = img.crop(box)
    side = int(max(mark.size) * 1.06)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(mark, ((side - mark.size[0]) // 2, (side - mark.size[1]) // 2))
    out = canvas.resize((size, size), Image.LANCZOS)
    if grey:
        g = out.convert("LA").convert("RGBA")
        g.putalpha(out.split()[3])
        out = g
    return out


def mac_icon(image, size=1024):
    """macOS's icon shape: an 824-point rounded square centred on a 1024
    canvas, with a soft shadow. Full-bleed iOS art gets shrunk into a grey
    frame by recent macOS, so the Mac gets its own version."""
    k = 4
    big = size * k
    inset, body = 100 * k, 824 * k
    radius = int(185.4 * k)
    art = image.convert("RGBA").resize((body, body), Image.LANCZOS)
    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, body - 1, body - 1], radius=radius, fill=255)
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset + 12 * k, inset + body, inset + body + 12 * k], radius=radius, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * k))
    canvas.alpha_composite(shadow)
    tile = Image.new("RGBA", (body, body), (0, 0, 0, 0))
    tile.paste(art, (0, 0), mask)
    canvas.alpha_composite(tile, (inset, inset))
    return canvas.resize((size, size), Image.LANCZOS)


def write_iconset(name, image):
    folder = os.path.join(CAT, f"{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.png"))
    mac_icon(image).save(os.path.join(folder, f"{name}-mac.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "%s.png",\n'
                '      "idiom" : "universal",\n      "platform" : "ios",\n'
                '      "size" : "1024x1024"\n    },\n    {\n      "filename" : "%s-mac.png",\n'
                '      "idiom" : "mac",\n      "scale" : "2x",\n      "size" : "512x512"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % (name, name))


def write_preview(name, image):
    folder = os.path.join(CAT, f"IconPreview-{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.resize((180, 180), Image.LANCZOS).save(os.path.join(folder, "preview.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "preview.png",\n'
                '      "idiom" : "universal"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


if __name__ == "__main__":
    night, day = app_icon(NIGHT), app_icon(DAY)
    write_iconset("AppIcon", night)
    write_iconset("AppIcon-Light", day)
    write_preview("Default", night)
    write_preview("Light", day)
    os.makedirs(ASSETS, exist_ok=True)
    for size in (48, 64, 96, 128, 256, 512):
        night.resize((size, size), Image.LANCZOS).save(os.path.join(ASSETS, f"icon-{size}.png"))
    for size in (64, 192, 512):
        rounded(night, size).save(os.path.join(ASSETS, f"web-icon-{size}.png"))
    maskable(night, NIGHT).save(os.path.join(ASSETS, "web-maskable-512.png"))
    for size in (16, 32):
        toolbar_glyph(size).save(os.path.join(ASSETS, f"icon-{size}.png"))
        toolbar_glyph(size, grey=True).save(os.path.join(ASSETS, f"icon-grey-{size}.png"))
    print("wrote AppIcon, AppIcon-Light, their previews, assets/icon-*.png and assets/web-*.png")

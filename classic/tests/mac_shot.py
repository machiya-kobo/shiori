#!/usr/bin/env python3
"""mac_shot.py: an emulator screenshot (scrot, the whole display) as the Mac's own
pixels, for the README and docs/screenshots.

    classic/tests/mac_shot.py snow IN.png OUT.png [--fb LEFT,TOP,SCALE] [--zoom 2]
        Snow draws the 512x342 screen scaled by a fraction (nearest neighbour): the
        screen's bounds are found from its white pixels, and each Mac pixel is read
        from the middle of its scaled block, giving the exact 512x342 image again.
        --fb takes snow_session.py's calibration ("Calibrated: FB_LEFT=…, FB_TOP=…, SCALE=…"),
        which is exact; without it the bounds are measured from the image.
    classic/tests/mac_shot.py basilisk IN.png OUT.png --origin X,Y --crop X,Y,W,H [--zoom 1]
        Basilisk II draws 1:1: the Mac screen starts at ORIGIN (basilisk_session.py
        prints it); CROP is a rectangle in Mac coordinates.

--zoom scales the result by whole pixels (nearest neighbour), so 1-bit text stays crisp.
"""
import argparse

from PIL import Image


def snow(img, fb=None):
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    def background(c):          # Snow's own dark grey around the Mac screen
        return all(abs(v - 27) <= 8 for v in c)

    # Snow's window: the run of background along a row under its toolbar
    row = 130
    cols = [x for x in range(w) if background(px[x, row])]
    wl, wr = min(cols), max(cols)
    # the Mac screen: what isn't background inside that window, under the toolbar
    left, right, top, bottom = w, 0, h, 0
    for y in range(row, h):
        for x in range(wl, wr + 1, 1):
            if not background(px[x, y]):
                left, right = min(left, x), max(right, x)
                top, bottom = min(top, y), max(bottom, y)
    right += 1
    bottom += 1
    gray = [[sum(px[x, y]) > 384 for x in range(w)] for y in range(h)]

    def fit(start, length, n, line):
        """The scale and offset along one axis whose sample points sit mid-block:
        a nearest-neighbour scaling makes each Mac pixel a uniform run."""
        best = None
        for k in range(-30, 31):
            sc = length / n * (1 + k / 4000.0)
            for off in (-1.0, -0.5, 0.0, 0.5, 1.0):
                bad = 0
                for i in range(n):
                    c = start + off + (i + 0.5) * sc
                    a, m, b = line(int(c - 0.3 * sc)), line(int(c)), line(int(c + 0.3 * sc))
                    bad += (a != m) + (b != m)
                if best is None or bad < best[0]:
                    best = (bad, sc, start + off)
        return best[1], best[2]

    # rows and columns rich in detail (the menu bar, a text line) decide the fit
    cols = [sum(gray[y][x] for y in range(top, bottom)) for x in range(w)]
    rows = [sum(gray[y][x] for x in range(left, right)) for y in range(h)]
    sx, fleft = fit(left, right - left, 512, lambda x: cols[min(max(x, 0), w - 1)])
    sy, ftop = fit(top, bottom - top, 342, lambda y: rows[min(max(y, 0), h - 1)])
    left, top = fleft, ftop
    out = Image.new("1", (512, 342))
    op = out.load()
    for my in range(342):
        y = int(top + (my + 0.5) * sy)
        for mx in range(512):
            x = int(left + (mx + 0.5) * sx)
            r, g, b = px[min(x, w - 1), min(y, h - 1)]
            op[mx, my] = 255 if (r + g + b) > 384 else 0
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("kind", choices=["snow", "basilisk"])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--zoom", type=int, default=0)
    ap.add_argument("--origin")
    ap.add_argument("--crop")
    ap.add_argument("--fb", help="snow: the driver's calibration FB_LEFT,FB_TOP,SCALE")
    a = ap.parse_args()
    img = Image.open(a.src)
    if a.kind == "snow":
        out = snow(img, tuple(float(v) for v in a.fb.split(",")) if a.fb else None)
        zoom = a.zoom or 2
    else:
        ox, oy = (int(v) for v in a.origin.split(","))
        x, y, w, h = (int(v) for v in a.crop.split(","))
        out = img.convert("RGB").crop((ox + x, oy + y, ox + x + w, oy + y + h))
        zoom = a.zoom or 1
    if zoom > 1:
        out = out.resize((out.width * zoom, out.height * zoom), Image.NEAREST)
    out.save(a.dst, optimize=True)
    print(a.dst, out.size)


if __name__ == "__main__":
    main()

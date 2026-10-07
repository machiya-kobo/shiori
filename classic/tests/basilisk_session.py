#!/usr/bin/env python3
"""Drives Basilisk II (System 7) for Shiori for Classic Macintosh, by XTEST.

    classic/tests/basilisk_session.py STEP [STEP…]

Coordinates are the Mac's own pixels (Basilisk draws at 1:1; the window's
content origin is found from the bright menu bar on each run).
    click:X,Y  dclick:X,Y   a click or double-click
    menu:X,Y                press on the menu title at X, drag to the item at Y, release
    peek:X                  hold the menu at X open, screenshot it (/tmp/shiori/peek.png), let go
    cmd:K                   Command-K (Basilisk maps the Super key to Command)
    type:TEXT               type plain text
    shot:NAME               /tmp/shiori/NAME.png
    wait:SECONDS
    shutdown                Special > Shut Down (never hard-kill Basilisk: it corrupts the disk)
Command keys sent by XTEST don't reach Basilisk here: use the menus.
Never use ImageMagick's import (it grabs the pointer); scrot only.
"""
import os
import subprocess
import sys
import time

from PIL import Image
from Xlib import X, XK, display
from Xlib.ext import xtest

SPECIAL_X, SHUT_DOWN_Y = 232, 139   # the Finder must be frontmost (quit Shiori first)

D = display.Display(os.environ.get("DISPLAY", ":0"))
ROOT = D.screen().root
ORIGIN = [0, 0]


def shot(name):
    os.makedirs("/tmp/shiori", exist_ok=True)
    path = "/tmp/shiori/%s.png" % name
    subprocess.run(["scrot", "-o", path], check=True)
    return path


def window_box():
    """The Basilisk II window's (x, y, w, h): the largest of its X windows."""
    best = None
    ids = subprocess.run(["xdotool", "search", "--class", "BasiliskII"], capture_output=True, text=True).stdout.split()
    for wid in ids:
        out = subprocess.run(["xdotool", "getwindowgeometry", "--shell", wid], capture_output=True, text=True).stdout
        g = dict(line.split("=", 1) for line in out.split() if "=" in line)
        if "WIDTH" in g and (best is None or int(g["WIDTH"]) * int(g["HEIGHT"]) > best[2] * best[3]):
            best = (int(g["X"]), int(g["Y"]), int(g["WIDTH"]), int(g["HEIGHT"]))
    return best


def calibrate():
    """The Mac screen's top-left. Its left edge and width are the Basilisk window's; its top
    is the first row near the window's reported top (which can be off by the frame) that is
    mostly bright: the top of the white menu bar."""
    img = Image.open(shot("_calibrate")).convert("L")
    w, h = img.size
    px = img.load()
    box = window_box()
    if box is None:
        print("Basilisk calibration failed: no window", flush=True)
        return
    bx, by, bw, _ = box
    def bright(y):
        return sum(1 for x in range(bx, min(w, bx + bw)) if px[x, y] > 200) >= 0.6 * bw

    # the first bright row right under a dark one (the frame's title bar), so the
    # wallpaper above the window never counts
    for y in range(max(1, by - 40), min(h, by + 60)):
        if bright(y) and not bright(y - 1):
            ORIGIN[0], ORIGIN[1] = bx, y
            print("Basilisk calibrated: origin", ORIGIN, flush=True)
            return
    print("Basilisk calibration failed; origin stays", ORIGIN, flush=True)


def move(mx, my):
    x, y = ORIGIN[0] + mx, ORIGIN[1] + my
    p = ROOT.query_pointer()
    for i in range(1, 16):
        xtest.fake_input(D, X.MotionNotify, x=int(p.root_x + (x - p.root_x) * i / 15),
                         y=int(p.root_y + (y - p.root_y) * i / 15))
        D.sync()
        time.sleep(0.015)
    time.sleep(0.15)


def button(press):
    xtest.fake_input(D, X.ButtonPress if press else X.ButtonRelease, 1)
    D.sync()


def click(mx, my, times=1):
    move(mx, my)
    for _ in range(times):
        button(True)
        time.sleep(0.05)
        button(False)
        time.sleep(0.12)


def key(sym, *mods):
    codes = [D.keysym_to_keycode(m) for m in mods]
    kc = D.keysym_to_keycode(sym)
    for c in codes:
        xtest.fake_input(D, X.KeyPress, c)
    xtest.fake_input(D, X.KeyPress, kc)
    D.sync()
    time.sleep(0.08)
    xtest.fake_input(D, X.KeyRelease, kc)
    for c in reversed(codes):
        xtest.fake_input(D, X.KeyRelease, c)
    D.sync()
    time.sleep(0.15)


def menu(mx, item_y, peek=False):
    move(mx, 10)
    button(True)
    time.sleep(0.6)
    if peek:
        shot("peek")
        move(mx + 300, 10)
    else:
        move(mx, item_y)
        time.sleep(0.3)
    button(False)
    time.sleep(0.5)


def main(steps):
    """Refuses to click anything until calibrated: a click outside the emulator (on the
    window manager's root) can start a grab that hangs the whole display."""
    try:
        subprocess.run(["xdotool", "search", "--class", "BasiliskII", "windowactivate"],
                       stderr=subprocess.DEVNULL, timeout=5)
    except subprocess.TimeoutExpired:
        pass
    calibrate()
    if ORIGIN == [0, 0] and any(s.split(":")[0] in ("click", "dclick", "menu", "peek", "shutdown") for s in steps):
        sys.exit("basilisk_session: not calibrated; refusing to click")
    for step in steps:
        print("step", step, flush=True)
        name, _, arg = step.partition(":")
        if name in ("click", "dclick"):
            x, y = (int(v) for v in arg.split(","))
            click(x, y, 2 if name == "dclick" else 1)
        elif name == "menu":
            x, y = (int(v) for v in arg.split(","))
            menu(x, y)
        elif name == "peek":
            menu(int(arg), 0, peek=True)
        elif name == "cmd":
            key(XK.string_to_keysym(arg), XK.XK_Super_L)
        elif name == "type":
            for ch in arg:
                sym = XK.XK_space if ch == " " else XK.string_to_keysym(ch)
                key(sym, *( [XK.XK_Shift_L] if ch.isupper() else []))
        elif name == "shot":
            print("shot", shot(arg))
        elif name == "wait":
            time.sleep(float(arg))
        elif name == "shutdown":
            # the Finder's Special menu (System 7.6.1): Shut Down is its last item
            menu(SPECIAL_X, SHUT_DOWN_Y)
        else:
            sys.exit("basilisk_session: unknown step %r" % step)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])

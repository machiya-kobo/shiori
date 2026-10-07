#!/usr/bin/env python3
"""Drives Shiori for Classic Macintosh in Snow (System 6), through the emulator hub's XTEST library.

    classic/tests/snow_session.py STEP [STEP…]

Steps, run in order (coordinates are the Mac's 512×342 screen, calibrated each run):
    open-app      open the disk's window, select Shiori, File > Open (⌘O); waits for launch
    probe         File > Run Probe (⌘R); waits for both requests
    da            Apple menu > Shiori Search (the desk accessory)
    cmd:K         Command-K (a letter; "period" for ⌘-., which stops a request)
    stop          ⌘-. (Escape on a Mac Plus keyboard)
    type:TEXT     types plain text (letters, digits, spaces)
    return        the Return key; down: the down arrow; tab: Tab
    click:X,Y     a click at Mac coordinates; dclick:X,Y a double-click
    close         close the front window (⌘W is not wired in the probe: clicks the go-away box)
    shot:NAME     a screenshot of the whole display, /tmp/shiori/NAME.png
    wait:SECONDS  sleep

Needs the disk set up by classic/scripts/setup-emulators.sh (only Shiori and the System at the
top level, so the Finder's list shows Shiori as its second row) and Snow running on DISPLAY=:0,
started by classic/scripts/deploy.sh snow --launch. Never use ImageMagick's import here: it grabs
the pointer and breaks Snow's mouse until restart.
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.environ.get("EMU", os.path.expanduser("~/emulators")), "scripts"))
from snow_automation import SnowAutomation  # noqa: E402

DISK_ICON = (471, 50)        # the startup disk on the desktop
SHIORI_ROW = (60, 287)       # Shiori, second row of the disk's list window
APPLE_MENU_X = 23
DA_ITEM_Y = 175              # last in the list: the System 6 disk has 7 DAs before it


def shot(name):
    os.makedirs("/tmp/shiori", exist_ok=True)
    subprocess.run(["scrot", "-o", "/tmp/shiori/%s.png" % name], env={**os.environ, "DISPLAY": ":0"}, check=True)
    print("shot /tmp/shiori/%s.png" % name)


def at(snow, mac_xy, double=False):
    x, y = snow.mac_to_screen(*mac_xy)
    snow.move_to(x, y)
    snow.jiggle()
    time.sleep(0.3)
    if double:
        snow.double_click()
    else:
        snow.click()


def main(steps):
    snow = SnowAutomation(auto_calibrate=True)
    for step in steps:
        print("step", step, flush=True)
        if step == "open-app":
            at(snow, DISK_ICON, double=True)
            time.sleep(4)
            at(snow, SHIORI_ROW)
            time.sleep(1)
            snow.cmd_key("o")
            time.sleep(10)
        elif step == "probe":
            snow.cmd_key("r")
            time.sleep(60)
        elif step.startswith("cmd:"):
            snow.cmd_key(step[4:])
            time.sleep(0.5)
        elif step == "stop":
            snow.cmd_key("period")          # XK has no keysym named "."
            time.sleep(0.5)
        elif step.startswith("type:"):
            snow.type_text(step[5:])
            time.sleep(0.5)
        elif step in ("return", "down", "up", "tab"):
            snow.key_sym_press({"return": "Return", "down": "Down", "up": "Up", "tab": "Tab"}[step])
            time.sleep(0.5)
        elif step.startswith("click:") or step.startswith("dclick:"):
            x, y = (int(v) for v in step.split(":", 1)[1].split(","))
            at(snow, (x, y), double=step.startswith("dclick:"))
            time.sleep(0.5)
        elif step == "da":
            snow.menu_select(APPLE_MENU_X, DA_ITEM_Y)
            time.sleep(4)
        elif step == "close":
            at(snow, (10, 28))
            time.sleep(2)
        elif step.startswith("shot:"):
            shot(step[5:])
        elif step.startswith("wait:"):
            time.sleep(float(step[5:]))
        else:
            sys.exit("snow_session: unknown step %r" % step)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])

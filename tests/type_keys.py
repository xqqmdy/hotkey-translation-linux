#!/usr/bin/env python3
"""Test helper: type an ASCII string (lowercase letters, colon, space,
digits) followed by Enter through uinput."""
import fcntl
import os
import struct
import sys
import time

EV_KEY, EV_SYN = 1, 0
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502

CODES = {
    "a": 30, "b": 48, "c": 46, "d": 32, "e": 18, "f": 33, "g": 34, "h": 35,
    "i": 23, "j": 36, "k": 37, "l": 38, "m": 50, "n": 49, "o": 24, "p": 25,
    "q": 16, "r": 19, "s": 31, "t": 20, "u": 22, "v": 47, "w": 17, "x": 45,
    "y": 21, "z": 44, " ": 57, ":": 39, "-": 12, ".": 52, "/": 53,
    "0": 11, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8,
    "8": 9, "9": 10, "_": 12,
}
SHIFTED = {":", "_"}
ENTER = 28
LEFTSHIFT = 42

text = sys.argv[1] if len(sys.argv) > 1 else ""
press_enter = "--no-enter" not in sys.argv

fd = os.open("/dev/uinput", os.O_WRONLY)
try:
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in set(CODES.values()) | {ENTER, LEFTSHIFT}:
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    os.write(fd, struct.pack("80sHHHHI64i64i64i64i", b"ht-typer",
                             0x06, 1, 1, 1, 0, *([0] * 256)))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.3)
    syn = struct.pack("qqHHi", 0, 0, EV_SYN, 0, 0)

    def key(code, value):
        os.write(fd, struct.pack("qqHHi", 0, 0, EV_KEY, code, value))
        os.write(fd, syn)
        time.sleep(0.02)

    for ch in text.lower() if text.isascii() else text:
        code = CODES.get(ch)
        if code is None:
            continue
        shift = ch in SHIFTED
        if shift:
            key(LEFTSHIFT, 1)
        key(code, 1)
        key(code, 0)
        if shift:
            key(LEFTSHIFT, 0)
        time.sleep(0.04)
    if press_enter:
        time.sleep(0.1)
        key(ENTER, 1)
        key(ENTER, 0)
    time.sleep(0.1)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    print("typed ok")
finally:
    os.close(fd)

#!/usr/bin/env python3
"""Test helper: synthesize a bare Enter key press via uinput."""
import fcntl
import os
import struct
import time

EV_KEY, EV_SYN = 1, 0
KEY_ENTER = 28
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502

fd = os.open("/dev/uinput", os.O_WRONLY)
try:
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_KEYBIT, KEY_ENTER)
    os.write(fd, struct.pack("80sHHHHI64i64i64i64i", b"zh2en-testkey",
                             0x06, 1, 1, 1, 0, *([0] * 256)))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.15)
    syn = struct.pack("qqHHi", 0, 0, EV_SYN, 0, 0)
    os.write(fd, struct.pack("qqHHi", 0, 0, EV_KEY, KEY_ENTER, 1))
    os.write(fd, syn)
    time.sleep(0.06)
    os.write(fd, struct.pack("qqHHi", 0, 0, EV_KEY, KEY_ENTER, 0))
    os.write(fd, syn)
    time.sleep(0.05)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    print("enter ok")
finally:
    os.close(fd)

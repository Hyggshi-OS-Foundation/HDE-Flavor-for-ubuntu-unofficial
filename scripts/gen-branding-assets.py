#!/usr/bin/env python3
"""Generate the NexWM OS branding images (installer logo + welcome slide).

The images are written with only the Python standard library so the build
never depends on image packages.  The output is deterministic (fixed pixel
values), so re-running it never changes a committed file byte for byte.

Files written (relative to the repository root):
  config/calamares/branding/nexwm-os/logo.png      512x512  -> productLogo / productIcon
  config/calamares/branding/nexwm-os/welcome.png  1200x600  -> productWelcome

Run it once on a workstation and commit the result:

    python3 scripts/gen-branding-assets.py
"""

import os
import struct
import zlib

WELCOME_W, WELCOME_H = 1200, 600
LOGO_W, LOGO_H = 512, 512
DARK = (0x17, 0x18, 0x24)          # near-black indigo background
ACCENT = (0x7C, 0x5C, 0xFF)        # violet accent (HDE/NexWM brand family)
TEXT = (0xE8, 0xE8, 0xF0)          # near-white


def png_write(path, width, height, rows):
    """Write a minimal RGB PNG (color type 2, 8-bit) from raw byte rows."""
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    chunk = lambda tag, data: struct.pack(">I", len(data)) + tag + data + \
        struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    payload = zlib.compress(raw, 9)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", ihdr))
        fh.write(chunk(b"IDAT", payload))
        fh.write(chunk(b"IEND", b""))


def blend(base, over, alpha):
    return tuple(round(b * (1 - alpha) + o * alpha) for b, o in zip(base, over))


def draw_h_logo(width, height, accent=ACCENT):
    """The HDE 'H' drawn the way the desktop theme does (crisp rectangles)."""
    rows = []
    bar_w = max(6, width // 16)
    bar_h = max(8, height // 2)
    left_x = width // 2 - bar_h // 2          # uses bar_h as the "H" height
    gap = max(3, width // 8)
    top = (height - bar_h) // 2
    cross_h = max(4, bar_h // 6)
    cross_y = top + bar_h // 2 - cross_h // 2
    right_x = left_x + bar_w + gap
    for y in range(height):
        row = []
        for x in range(width):
            in_bar = (left_x <= x < left_x + bar_w) or (right_x <= x < right_x + bar_w)
            in_cross = cross_y <= y < cross_y + cross_h and left_x + bar_w <= right_x
            col = DARK
            if in_bar or in_cross:
                col = accent
            row.extend(col)
        rows.append(row)
    return rows


def draw_welcome(width, height):
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            base = DARK
            # A soft diagonal accent wash, brighter toward the top-right.
            wash = max(0.0, (x / width) * 0.55 + (1 - y / height) * 0.45)
            # Horizontal accent bar along the bottom.
            bar = height // 24 <= y < height // 16
            if bar:
                base = blend(DARK, ACCENT, 0.85)
            else:
                base = blend(DARK, (0x35, 0x30, 0x60), 0.55 * wash)
            row.extend(base)
        rows.append(row)
    return rows


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    brand = os.path.join(repo, "config", "calamares", "branding", "nexwm-os")
    png_write(os.path.join(brand, "logo.png"), LOGO_W, LOGO_H, draw_h_logo(LOGO_W, LOGO_H))
    png_write(os.path.join(brand, "welcome.png"), WELCOME_W, WELCOME_H, draw_welcome(WELCOME_W, WELCOME_H))
    print(f"branding assets written to {brand}")


if __name__ == "__main__":
    main()

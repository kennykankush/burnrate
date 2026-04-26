#!/usr/bin/env python3
import os
import sys
from PIL import Image

LIGHT_LO = 225
LIGHT_HI = 248
GRAY_TOL = 12

def key_image(src_path, dst_path):
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            mx = max(r, g, b)
            mn = min(r, g, b)
            if mx - mn <= GRAY_TOL and mn >= LIGHT_LO:
                if mn >= LIGHT_HI:
                    px[x, y] = (r, g, b, 0)
                else:
                    a = int(255 * (LIGHT_HI - mn) / (LIGHT_HI - LIGHT_LO))
                    px[x, y] = (r, g, b, a)
    img.save(dst_path, "PNG", optimize=True)

if __name__ == "__main__":
    src_dir, dst_dir = sys.argv[1], sys.argv[2]
    os.makedirs(dst_dir, exist_ok=True)
    for name in os.listdir(src_dir):
        if not name.endswith(".png"):
            continue
        key_image(os.path.join(src_dir, name), os.path.join(dst_dir, name))
        print(f"keyed {name}")

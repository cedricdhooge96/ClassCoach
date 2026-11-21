#!/usr/bin/env python3
"""Draws ClassCoach's own artwork: python3 tools/gen_textures.py (needs Pillow).

The game cannot draw circles or vector shapes, so every round shape is a
texture file: 32-bit TGA with alpha, sides a power of two. Each one is white on
transparent and coloured in the game (SetVertexColor), so one file serves every
colour. Shapes are drawn four times too large and scaled down for smooth edges.
"""
import os
import struct

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ClassCoach", "Media")
OVER = 4  # draw at four times the size, then scale down


def canvas(size):
    return Image.new("L", (size * OVER, size * OVER), 0)


def ring(size, stroke, margin=1.0):
    """A ring that fills the texture: `stroke` is its thickness as a share of the diameter."""
    img = canvas(size)
    d = ImageDraw.Draw(img)
    edge = margin * OVER
    full = size * OVER
    d.ellipse([edge, edge, full - edge, full - edge], fill=255)
    inner = edge + stroke * (full - 2 * edge)
    d.ellipse([inner, inner, full - inner, full - inner], fill=0)
    return img.resize((size, size), Image.LANCZOS)


def disc(size, margin=1.0):
    img = canvas(size)
    edge = margin * OVER
    full = size * OVER
    ImageDraw.Draw(img).ellipse([edge, edge, full - edge, full - edge], fill=255)
    return img.resize((size, size), Image.LANCZOS)


def glow(size):
    """A soft ring for the "press this now" pulse: it is drawn additively and grows outward."""
    img = ring(size, 0.10, margin=size * 0.14)
    return img.filter(ImageFilter.GaussianBlur(size * 0.035))


def halo(size):
    """A soft square frame for lighting up an action button. The frame's edge sits
    a quarter of the way in, so the glow spills evenly around the button."""
    img = canvas(size)
    d = ImageDraw.Draw(img)
    inset, stroke, corner = size * 0.25 * OVER, size * 0.05 * OVER, size * 0.06 * OVER
    full = size * OVER
    d.rounded_rectangle([inset - stroke, inset - stroke, full - inset + stroke, full - inset + stroke], radius=corner + stroke, fill=255)
    d.rounded_rectangle([inset, inset, full - inset, full - inset], radius=corner, fill=0)
    img = img.resize((size, size), Image.LANCZOS)
    soft = img.filter(ImageFilter.GaussianBlur(size * 0.045))
    return Image.eval(Image.blend(img, soft, 0.7), lambda v: min(255, int(v * 1.8)))


def save(name, alpha):
    size = alpha.size[0]
    assert alpha.size == (size, size) and size & (size - 1) == 0, "sides must be a power of two"
    white = Image.new("L", alpha.size, 255)
    path = os.path.join(OUT, name + ".tga")
    Image.merge("RGBA", (white, white, white, alpha)).save(path, format="TGA")
    # The form known to load in WoW Forever: uncompressed true colour, 32 bits, 8 alpha bits.
    with open(path, "rb") as f:
        head = f.read(18)
    kind, bits, descriptor = head[2], head[16], head[17]
    width, height = struct.unpack("<HH", head[12:16])
    assert (kind, bits, width, height) == (2, 32, size, size) and descriptor & 0x0F == 8, (kind, bits, descriptor)
    print("%-10s %dx%d  %d bytes" % (name, size, size, os.path.getsize(path)))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("ring", ring(128, 3 / 84))        # around the current step: 3 units thick at 84 across
    save("ring_bold", ring(64, 3 / 34))    # around a "before you pull" mark: 3 units at 34 across
    save("disc", disc(128))                # the dark ground behind a round icon
    save("pulse", glow(128))               # the cue when a new key is needed
    save("halo", halo(128))                # the glow around the action-bar button to press

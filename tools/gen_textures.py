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


def pill(size):
    """A capsule for the settings switches: it fills the middle half of the texture
    (use SetTexCoord(0, 1, 0.25, 0.75)), so the file stays square."""
    img = canvas(size)
    full = size * OVER
    top, bottom = full * 0.25 + OVER, full * 0.75 - OVER
    ImageDraw.Draw(img).rounded_rectangle([OVER, top, full - OVER, bottom], radius=(bottom - top) / 2, fill=255)
    return img.resize((size, size), Image.LANCZOS)


def bevel(size, stroke, margin=1.0):
    """The gold ring with depth: light on the top edge, darker below, and a thin dark
    line on the inside. Drawn in grey (tinted gold in the game, which multiplies), so
    the light parts come out as light gold and the dark parts as deep gold."""
    shape = ring(size, stroke, margin)
    shade = Image.new("L", (size, size), 0)
    px = shade.load()
    for y in range(size):
        light = 255 - int(95 * y / (size - 1))   # 255 at the top, 160 at the bottom
        for x in range(size):
            px[x, y] = light
    inner = ring(size, stroke * 0.22, margin + stroke * (size - 2 * margin) * 0.78)
    shade = Image.composite(Image.new("L", (size, size), 70), shade, inner)
    return shade, shape


def soft_disc(size, reach=0.62):
    """A shadow that fades out around a round shape: dark in the middle, nothing at the edge."""
    img = canvas(size)
    full = size * OVER
    r = full * reach / 2
    ImageDraw.Draw(img).ellipse([full / 2 - r, full / 2 - r, full / 2 + r, full / 2 + r], fill=255)
    img = img.resize((size, size), Image.LANCZOS)
    return img.filter(ImageFilter.GaussianBlur(size * 0.09))


def plate(size, radius):
    """A filled rounded rectangle for nine-slice drawing: SetTextureSliceMargins(m, m, m, m)
    with m = size / 4 keeps the corners round at any panel size."""
    img = canvas(size)
    full = size * OVER
    ImageDraw.Draw(img).rounded_rectangle([OVER, OVER, full - OVER, full - OVER], radius=radius * OVER, fill=255)
    return img.resize((size, size), Image.LANCZOS)


def plate_shadow(size, radius):
    """The same rounded shape, blurred: a soft shadow that spills out around a panel."""
    img = canvas(size)
    full = size * OVER
    inset = size * 0.25 * OVER
    ImageDraw.Draw(img).rounded_rectangle([inset, inset, full - inset, full - inset], radius=radius * OVER, fill=255)
    img = img.resize((size, size), Image.LANCZOS)
    return img.filter(ImageFilter.GaussianBlur(size * 0.07))


def wash(width, height):
    """A soft oval of light under the coach, like a lantern on the ground. Tinted in the
    game: your class colour, amber before a pull, ember in a fight."""
    img = Image.new("L", (width * OVER, height * OVER), 0)
    ImageDraw.Draw(img).ellipse([width * OVER * 0.12, height * OVER * 0.18, width * OVER * 0.88, height * OVER * 0.82], fill=255)
    img = img.resize((width, height), Image.LANCZOS)
    return img.filter(ImageFilter.GaussianBlur(height * 0.16))


def save(name, alpha, light=None):
    """`light` is the grey of each pixel (white when not given); `alpha` its cover."""
    width, height = alpha.size
    assert width & (width - 1) == 0 and height & (height - 1) == 0, "sides must be a power of two"
    white = light or Image.new("L", alpha.size, 255)
    path = os.path.join(OUT, name + ".tga")
    Image.merge("RGBA", (white, white, white, alpha)).save(path, format="TGA")
    # The form known to load in WoW Forever: uncompressed true colour, 32 bits, 8 alpha bits.
    with open(path, "rb") as f:
        head = f.read(18)
    kind, bits, descriptor = head[2], head[16], head[17]
    w, h = struct.unpack("<HH", head[12:16])
    assert (kind, bits, w, h) == (2, 32, width, height) and descriptor & 0x0F == 8, (kind, bits, descriptor)
    print("%-12s %dx%d  %d bytes" % (name, width, height, os.path.getsize(path)))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("ring", ring(256, 3 / 84))        # around the current step: 3 units thick at 84 across (256: sharp at 1440p and 4K)
    save("ring_bold", ring(64, 3 / 34))    # around a "before you pull" mark: 3 units at 34 across
    save("disc", disc(128))                # the dark ground behind a round icon
    save("pulse", glow(128))               # the cue when a new key is needed
    save("halo", halo(128))                # the glow around the action-bar button to press
    save("pill", pill(64))                 # the track of a switch in the settings window
    # "Lantern": depth and light for ClassCoach's own frames
    light, shape = bevel(256, 4 / 84)
    save("ring_bevel", shape, light)       # the gold ring with a light top edge and a dark inner line
    save("ring_shadow", soft_disc(256))    # the soft dark pool behind the ring
    save("plate", plate(64, 10))           # rounded panel, nine-slice with margins of 16
    save("plate_shadow", plate_shadow(128, 10))  # its soft shadow, nine-slice with margins of 40
    save("wash", wash(256, 128))           # the lantern light under the coach

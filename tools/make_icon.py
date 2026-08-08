"""Generates Omni's launcher icon.

The mark is an "O" built from five arcs, one per network Omni aggregates —
the app's whole premise in a shape that still reads at 48px.
"""

import os
from PIL import Image, ImageDraw

SS = 4  # supersample factor; everything is drawn big and downsampled
BASE = 1024

# Network colours, ordered so no two similar hues sit next to each other —
# the two oranges end up on opposite sides of the ring.
SEGMENTS = [
    (0x11, 0x85, 0xFE),  # Bluesky
    (0xF2, 0x65, 0x22),  # RSS
    (0x63, 0x64, 0xFF),  # Mastodon
    (0xFF, 0x45, 0x00),  # Reddit
    (0xFF, 0xFF, 0xFF),  # X
]

BG_TOP = (0x2A, 0x22, 0x45)
BG_BOTTOM = (0x12, 0x10, 0x1C)


def gradient(size):
    img = Image.new("RGB", (1, size), BG_TOP)
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(
            round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
        )
    return img.resize((size, size), Image.NEAREST)


def draw_ring(size, outer_frac, thickness_frac):
    """The five-arc O, on a transparent canvas."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = cy = s / 2
    outer = s * outer_frac
    inner = outer - s * thickness_frac

    gap = 13.0
    span = (360.0 - gap * len(SEGMENTS)) / len(SEGMENTS)
    # Start at the top and go clockwise.
    angle = -90.0 + gap / 2

    # Solid wedges first, then the middle is punched out, which keeps the
    # segment ends flat and the gaps exactly as wide as specified.
    for colour in SEGMENTS:
        d.pieslice(
            [cx - outer, cy - outer, cx + outer, cy + outer],
            angle,
            angle + span,
            fill=colour + (255,),
        )
        angle += span + gap

    # ImageDraw writes raw pixel values, so filling with a zero alpha erases.
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=(0, 0, 0, 0))

    return img.resize((size, size), Image.LANCZOS)


def legacy_icon(size):
    """Full-bleed square icon for launchers without adaptive support."""
    img = gradient(size).convert("RGBA")
    ring = draw_ring(size, outer_frac=0.36, thickness_frac=0.115)
    img.alpha_composite(ring)

    # Round the corners so it doesn't look like a raw square when unmasked.
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS - 1, size * SS - 1],
        radius=size * SS * 0.22,
        fill=255,
    )
    img.putalpha(mask.resize((size, size), Image.LANCZOS))
    return img


def adaptive_foreground(size):
    """Adaptive foreground: the mark, kept inside the safe zone Android masks."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # 108dp canvas, only the middle ~66dp is guaranteed visible.
    img.alpha_composite(draw_ring(size, outer_frac=0.245, thickness_frac=0.078))
    return img


def adaptive_background(size):
    return gradient(size).convert("RGBA")


RES = "/home/user/Omni/android/app/src/main/res"

LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# Adaptive layers are 108dp on the same density ladder.
ADAPTIVE = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

for folder, px in LEGACY.items():
    os.makedirs(f"{RES}/{folder}", exist_ok=True)
    legacy_icon(px).save(f"{RES}/{folder}/ic_launcher.png")

for folder, px in ADAPTIVE.items():
    adaptive_foreground(px).save(f"{RES}/{folder}/ic_launcher_foreground.png")
    adaptive_background(px).save(f"{RES}/{folder}/ic_launcher_background.png")

# A large copy for listings and the README.
legacy_icon(BASE).save(
    "docs/icon.png"
)
print("icons written")

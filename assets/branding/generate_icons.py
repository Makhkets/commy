"""Generate the Commy app icon.

The mark is the same power glyph the connect button uses: a broken ring with a
vertical stem. That is deliberate — the icon and the one control in the product
should be the same shape, so the launcher icon reads as "the button" before the
app is even open.

Palette comes straight from the semantic tokens (docs/04-design-system.md):
graphite background, jade glyph. No new colours are invented here.
"""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "icon-out")
os.makedirs(OUT, exist_ok=True)

BG_CANVAS = (10, 11, 13)      # bg/canvas   #0A0B0D
BG_RAISED = (27, 29, 33)      # bg/raised   #1B1D21
JADE = (47, 217, 138)         # status/connected #2FD98A
BORDER = (36, 39, 44)         # border/default #24272C

SS = 8  # supersample factor; Pillow has no AA for arcs, so we draw big and shrink


def power_glyph(d, cx, cy, r, width, colour):
    """Ring open at the top plus a vertical stem — the IEC 5009 power symbol."""
    gap = 54  # degrees of opening, centred on 12 o'clock
    start = -90 + gap / 2
    end = 270 - gap / 2
    d.arc([cx - r, cy - r, cx + r, cy + r], start, end, fill=colour, width=width)
    # The stem starts just outside the ring and stops well short of the centre —
    # in the Figma button it reaches roughly halfway down the radius, not to the
    # middle. Going deeper makes the glyph read as a thermometer.
    stem_top = cy - r - width * 0.45
    stem_bottom = cy - r * 0.46
    d.line([(cx, stem_top), (cx, stem_bottom)], fill=colour, width=width)
    # round the stem caps so it matches the 1.75 stroke / rounded-ends icon rule
    rr = width / 2
    for y in (stem_top, stem_bottom):
        d.ellipse([cx - rr, y - rr, cx + rr, y + rr], fill=colour)


def render(size, *, background=True, margin_ratio=0.0, rounded=False):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if background:
        if rounded:
            radius = int(s * 0.22)  # matches radius/xl at this scale
            d.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=BG_CANVAS)
            d.rounded_rectangle(
                [0, 0, s - 1, s - 1], radius=radius, outline=BORDER,
                width=max(1, int(s * 0.008)),
            )
        else:
            d.rectangle([0, 0, s, s], fill=BG_CANVAS)
        # the raised disc the glyph sits on, same as the connect button
        disc = s * 0.62
        off = (s - disc) / 2
        d.ellipse([off, off, off + disc, off + disc], fill=BG_RAISED)

    # margin_ratio shrinks the glyph for adaptive icons, whose safe zone is
    # only the middle ~66% of the canvas.
    usable = s * (1 - margin_ratio * 2)
    r = usable * 0.20
    width = max(2, int(usable * 0.052))
    power_glyph(d, s / 2, s / 2 + usable * 0.018, r, width, JADE)

    return img.resize((size, size), Image.LANCZOS)


# ---- Android mipmaps -------------------------------------------------------
LAUNCHER = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for name, px in LAUNCHER.items():
    p = os.path.join(OUT, f"mipmap-{name}")
    os.makedirs(p, exist_ok=True)
    render(px, rounded=True).save(os.path.join(p, "ic_launcher.png"))
    # adaptive foreground: glyph only, transparent, drawn inside the safe zone
    render(int(px * 108 / 48), background=False, margin_ratio=0.17).save(
        os.path.join(p, "ic_launcher_foreground.png")
    )

# ---- store / readme --------------------------------------------------------
render(512, rounded=True).save(os.path.join(OUT, "icon-512.png"))
render(1024, rounded=True).save(os.path.join(OUT, "icon-1024.png"))
render(192, rounded=True).save(os.path.join(OUT, "icon-192.png"))

# flat background colour for the adaptive icon's background layer
Image.new("RGBA", (108, 108), BG_CANVAS + (255,)).save(
    os.path.join(OUT, "ic_launcher_background.png")
)

print("wrote:")
for root, _, files in os.walk(OUT):
    for f in sorted(files):
        fp = os.path.join(root, f)
        print(f"  {os.path.relpath(fp, OUT)}  {os.path.getsize(fp)} B")

"""Draw the iClean app icon.

Everything is drawn at 4x and downsampled at the end, because Pillow's shape
drawing is aliased — supersampling is what makes the edges clean.

Design: a stack of photo cards on the app's own accent blue, the front one
crisp and the ones behind it receding, with a green check badge. One shape,
no text, legible at 60px.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # supersample factor
SIDE = 1024
N = SIDE * S


def px(v):
    """1024-space value -> canvas pixels."""
    return int(round(v * S))


# ---------------------------------------------------------------- background
# Bilinear-interpolated corner gradient: a tiny image blown up is the simplest
# way to get a smooth diagonal without per-pixel work.
TOP_LEFT = (58, 141, 224)
TOP_RIGHT = (36, 116, 206)
BOTTOM_LEFT = (18, 92, 184)
BOTTOM_RIGHT = (9, 62, 148)

seed = Image.new("RGB", (2, 2))
seed.putpixel((0, 0), TOP_LEFT)
seed.putpixel((1, 0), TOP_RIGHT)
seed.putpixel((0, 1), BOTTOM_LEFT)
seed.putpixel((1, 1), BOTTOM_RIGHT)
icon = seed.resize((N, N), Image.BICUBIC).convert("RGBA")


def card(w, h, fill, radius=64, motif=False):
    """A photo card as its own RGBA layer, so it can be rotated independently."""
    layer = Image.new("RGBA", (px(w), px(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([0, 0, px(w) - 1, px(h) - 1], radius=px(radius), fill=fill)

    if motif:
        # A simple photograph: sun plus two hills. Deliberately low-detail —
        # anything finer turns to mush at 60px.
        inset = px(46)
        photo = [inset, inset, px(w) - inset, px(h) - inset]
        d.rounded_rectangle(photo, radius=px(24), fill=(214, 230, 246, 255))

        # The hills are drawn oversized and then clipped to the photo rect, so
        # they meet its rounded corners exactly instead of poking past them.
        hills = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hills)
        hd.ellipse([px(w) * 0.60, inset + px(40), px(w) * 0.60 + px(96), inset + px(136)],
                   fill=(255, 200, 92, 255))
        hd.polygon([(px(w) * 0.02, px(h)), (px(w) * 0.42, px(h) * 0.44),
                    (px(w) * 0.80, px(h))], fill=(88, 152, 112, 255))
        hd.polygon([(px(w) * 0.34, px(h)), (px(w) * 0.66, px(h) * 0.58),
                    (px(w) * 0.99, px(h))], fill=(124, 190, 138, 255))

        clip = Image.new("L", layer.size, 0)
        ImageDraw.Draw(clip).rounded_rectangle(photo, radius=px(24), fill=255)
        hills.putalpha(Image.composite(hills.getchannel("A"), Image.new("L", layer.size, 0), clip))
        layer.alpha_composite(hills)

    return layer


def place(base, layer, cx, cy, angle=0.0, shadow=True):
    """Composite `layer` centred on (cx, cy) in 1024-space, optionally rotated."""
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = px(cx) - layer.width // 2
    y = px(cy) - layer.height // 2

    if shadow:
        sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
        silhouette = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        silhouette.putalpha(layer.getchannel("A").point(lambda a: int(a * 0.30)))
        sh.paste(silhouette, (x, y + px(10)), silhouette)
        sh = sh.filter(ImageFilter.GaussianBlur(px(14)))
        base.alpha_composite(sh)

    tmp = Image.new("RGBA", base.size, (0, 0, 0, 0))
    tmp.paste(layer, (x, y), layer)
    base.alpha_composite(tmp)
    return base


# ------------------------------------------------------------------ the stack
# Back cards are tinted rather than translucent: over a gradient, translucency
# makes them read as smudges instead of as photos behind photos.
icon = place(icon, card(450, 450, (150, 187, 230, 255)), 556, 396, angle=-16)
icon = place(icon, card(480, 480, (203, 224, 245, 255)), 524, 438, angle=-8)
icon = place(icon, card(520, 520, (255, 255, 255, 255), motif=True), 480, 512, angle=0)

# ------------------------------------------------------------------- the badge
BADGE_R = 132
BADGE_CX, BADGE_CY = 742, 742
badge = Image.new("RGBA", (px(BADGE_R * 2), px(BADGE_R * 2)), (0, 0, 0, 0))
bd = ImageDraw.Draw(badge)
bd.ellipse([0, 0, px(BADGE_R * 2) - 1, px(BADGE_R * 2) - 1], fill=(255, 255, 255, 255))
bd.ellipse([px(15), px(15), px(BADGE_R * 2 - 15), px(BADGE_R * 2 - 15)], fill=(48, 190, 90, 255))
bd.line([(px(66), px(133)), (px(114), px(180)), (px(198), px(92))],
        fill=(255, 255, 255, 255), width=px(30), joint="curve")
# Round the stroke ends — a check with square ends looks broken at small sizes.
for cx, cy in [(66, 133), (198, 92)]:
    bd.ellipse([px(cx - 15), px(cy - 15), px(cx + 15), px(cy + 15)], fill=(255, 255, 255, 255))
icon = place(icon, badge, BADGE_CX, BADGE_CY)

# ----------------------------------------------------------------------- out
final = icon.resize((SIDE, SIDE), Image.LANCZOS).convert("RGB")
final.save("icon-1024.png")
final.resize((180, 180), Image.LANCZOS).save("icon-180.png")
final.resize((60, 60), Image.LANCZOS).save("icon-60.png")
print("wrote icon-1024.png, icon-180.png, icon-60.png")

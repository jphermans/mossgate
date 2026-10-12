#!/usr/bin/env python3
"""Build the Mossgate app icon, in the appearances iOS 26 asks for.

The icon is composed from the game's own art: the lit lantern out of checkpoint.png, over a
dusk sky whose colours are sampled from a real in-game frame. Everything is drawn on ONE pixel
grid of ZxZ blocks — the sprite by an exact integer zoom, the sky in blocks of the same size —
so no pixel is ever half a pixel, which is the difference between pixel art and a picture of
pixel art.

iOS 26 does not want one icon. It wants three appearances:

  light   the default, for a light home screen
  dark    a genuinely darker rendition, NOT the default dimmed
  tinted  strictly grayscale — the system overlays the user's tint on it

All three are the SAME composition relit, one palette swap apart, so they cannot drift. The
tinted one is verified gray by scanning the output for chroma, because anything coloured
renders wrong under the tint engine.
"""

from PIL import Image, ImageDraw

SPRITE = "Resources/Sprites/checkpoint.png"
OUTDIR = "Assets.xcassets/AppIcon.appiconset"

SIZE = 1024
Z = 6                     # the pixel size of the icon; everything snaps to ZxZ blocks


def is_glass(r, g, b, a):
    """The lantern's lit glass: warm and bright. Blue above green is the test for the
    sprites' magenta outline, and this is its exact inverse, so the two cannot overlap."""
    return a > 40 and r > 120 and r > b + 40 and g > 60


# --- palettes. Light is sampled from a real in-game frame; dark and tinted are the same
#     composition relit rather than separate artwork.
#
#     The first Light pass used the in-game night sky literally — (5, 8, 38) at the top. That
#     was ACCURATE and the VALUE was wrong: an app icon is read at 60pt on a bright home
#     screen, where a near-black sky just reads as a dark square. Asked for as "make the icon
#     what lighter it is too dark". These are dusk, not night.
LIGHT = dict(
    sky=[(42, 60, 124), (52, 74, 138), (66, 92, 148), (78, 112, 150)],
    firs=(44, 70, 76), ground=(96, 122, 58), ground_lit=(140, 172, 76),
    moon=(250, 242, 226), moon_shade=(188, 178, 160),
    star=(252, 246, 232), star_dim=(196, 188, 170),
    glow=(255, 178, 84), glow_alpha=0.55, lantern="colour",
)
DARK = dict(
    sky=[(10, 16, 44), (14, 22, 52), (18, 30, 60), (22, 38, 64)],
    firs=(16, 30, 34), ground=(44, 60, 26), ground_lit=(66, 88, 34),
    moon=(210, 200, 182), moon_shade=(130, 120, 106),
    star=(220, 210, 192), star_dim=(116, 110, 98),
    glow=(255, 158, 56), glow_alpha=0.55, lantern="colour",
)
TINTED = dict(
    sky=[(44, 44, 44), (54, 54, 54), (64, 64, 64), (74, 74, 74)],
    firs=(34, 34, 34), ground=(88, 88, 88), ground_lit=(118, 118, 118),
    moon=(190, 190, 190), moon_shade=(130, 130, 130),
    star=(200, 200, 200), star_dim=(140, 140, 140),
    glow=(150, 150, 150), glow_alpha=0.0, lantern="mono",
)

STARS = [(60, 70), (150, 130), (250, 55), (350, 175), (860, 90), (930, 200),
         (80, 260), (200, 330), (900, 300), (820, 430), (120, 480), (960, 520),
         (55, 620), (170, 700), (880, 660), (940, 780), (300, 260), (420, 120),
         (560, 200), (660, 90), (740, 260), (30, 400), (990, 380), (620, 330)]
BRIGHT_STARS = [(150, 130), (860, 90), (300, 260)]


def snap(v):
    """Round a coordinate onto the Z grid."""
    return int(round(v / Z)) * Z


def bayer(x, y):
    """4x4 ordered dither threshold, 0..15. Pixel-art gradients dither, they do not blend."""
    m = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    return m[(y // Z) % 4][(x // Z) % 4]


def band(img, y0, y1, c0, c1):
    """A horizontal band dithered from c0 to c1, in whole Z-cells."""
    px = img.load()
    y0, y1 = snap(y0), snap(y1)
    cells = max(1, (y1 - y0) // Z)
    for y in range(y0, y1):
        t = ((y - y0) // Z) / max(1, cells - 1)
        for x in range(0, SIZE, Z):
            c = c1 if (bayer(x, y) / 16.0) < t else c0
            for dx in range(Z):
                for dy in range(Z):
                    if x + dx < SIZE and y + dy < SIZE:
                        px[x + dx, y + dy] = c


def lantern_sprite():
    """The lantern, cropped out of the game's checkpoint sprite.

    Cropped to the lantern and not the whole sprite: the full sprite is a post with a lantern
    on it, and at any size that fits the frame the lantern is about 7% of the icon's width and
    invisible at 60pt. Cropped, it is 31% and reads.

    It is found by GEOMETRY rather than by warm-pixel density. The post is lit by the lantern
    and its lit face has MORE warm pixels per column than the glass does, so no threshold
    separates the two, and a permissive one drags the post in as a plank down the left side.
    The lantern is the rightmost group of warm pixels, and its rows carry the most of them.
    """
    sp = Image.open(SPRITE).convert("RGBA")
    w, h = sp.size
    src = sp.load()
    rows, cols = {}, {}
    for y in range(h):
        for x in range(int(w * 0.44), w):
            r, g, b, a = src[x, y]
            if is_glass(r, g, b, a):
                rows[y] = rows.get(y, 0) + 1
                cols[x] = cols.get(x, 0) + 1

    def runs_of(hist, gap=3):
        keys = sorted(hist)
        if not keys:
            return []
        out, lo, prev = [], keys[0], keys[0]
        for k in keys[1:]:
            if k - prev > gap:
                out.append((lo, prev))
                lo = k
            prev = k
        out.append((lo, prev))
        return out

    col_runs, row_runs = runs_of(cols), runs_of(rows)
    if not col_runs or not row_runs:
        raise SystemExit("no lantern found in the sprite — the warm-pixel test needs revisiting")
    left, right = col_runs[-1]                                  # rightmost object
    ty, by = max(row_runs, key=lambda r: sum(rows.get(y, 0) for y in range(r[0], r[1] + 1)))

    # The top goes at the lantern's own cap. Cutting where the warm rows stop slices the
    # hanger in half and leaves a notch that reads as damage; following the silhouette up from
    # the glass until the object ends lands on the flat top of the cap, which looks deliberate
    # because it is the shape of the thing.
    gl, gr = max(0, left - 4), min(w, right + 5)
    cap_top = ty
    while cap_top > 0:
        if not any(sp.getpixel((x, cap_top - 1))[3] > 40 for x in range(gl, gr)):
            break
        cap_top -= 1

    lan = sp.crop((max(0, left - 20), max(0, cap_top - 1), min(w, right + 21), min(h, by + 24)))

    # The sprites carry a magenta outline: a dark edge in-game at 1.6x, a glaring pink fringe
    # at 6x. Remapped to the frame's dark brass, keeping the silhouette it drew and dropping
    # the pink.
    p = lan.load()
    for y in range(lan.height):
        for x in range(lan.width):
            r, g, b, a = p[x, y]
            if a > 40 and b > g + 8 and r > 80:
                p[x, y] = (54, 38, 28, a)
    return lan


def mono_lantern(lan):
    """The lantern as a gray mask with its glass pushed to white.

    iOS overlays the user's tint on the tinted appearance, so anything coloured renders wrong.
    The guidance is one prominent white element with the rest stepped down to grays — the lit
    glass is the obvious candidate, and it is also what makes the icon recognisable as a
    silhouette rather than a blob.
    """
    out = Image.new("RGBA", lan.size)
    src, dst = lan.load(), out.load()
    for y in range(lan.height):
        for x in range(lan.width):
            r, g, b, a = src[x, y]
            if a == 0:
                dst[x, y] = (0, 0, 0, 0)
            elif is_glass(r, g, b, a):
                dst[x, y] = (255, 255, 255, a)
            else:
                v = int(0.55 * (0.299 * r + 0.587 * g + 0.114 * b))
                dst[x, y] = (v, v, v, a)
    return out


def build(pal):
    icon = Image.new("RGB", (SIZE, SIZE), pal["sky"][0])
    d = ImageDraw.Draw(icon)

    # 1. Sky. Dark at the top, warming toward the horizon.
    band(icon, 0, 300, pal["sky"][0], pal["sky"][1])
    band(icon, 300, 560, pal["sky"][1], pal["sky"][2])
    band(icon, 560, 800, pal["sky"][2], pal["sky"][3])
    band(icon, 800, 960, pal["sky"][3], pal["sky"][2])

    # 2. Stars: single Z-cells, a few with a faint cross so they are not all identical.
    for (x, y) in STARS:
        d.rectangle([snap(x), snap(y), snap(x) + Z - 1, snap(y) + Z - 1], fill=pal["star"])
    for (x, y) in BRIGHT_STARS:
        for (dx, dy) in [(-1, 0), (1, 0), (0, 1)]:
            d.rectangle([snap(x) + dx * Z, snap(y) + dy * Z,
                         snap(x) + dx * Z + Z - 1, snap(y) + dy * Z + Z - 1],
                        fill=pal["star_dim"])

    # 3. Crescent moon, upper left, clear of the lantern so the two do not compete.
    mx, my, mr = snap(190), snap(170), snap(88)
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=pal["moon"])
    d.ellipse([mx - mr + snap(48), my - mr - snap(22), mx + mr + snap(56), my + mr - snap(10)],
              fill=pal["sky"][0])
    d.arc([mx - mr + snap(48), my - mr - snap(22), mx + mr + snap(56), my + mr - snap(10)],
          150, 250, fill=pal["moon_shade"], width=Z)

    # 4. Distant firs, a step or two off the sky so they read as far away rather than near.
    for base_x, peak, height in [(70, 985, 230), (330, 950, 300), (640, 975, 250),
                                 (900, 955, 290)]:
        half = height * 0.42
        d.polygon([(snap(base_x), snap(peak - height)), (snap(base_x - half), snap(peak)),
                   (snap(base_x + half), snap(peak))], fill=pal["firs"])

    # 5. Ground, with a lit top edge so the lantern has something to stand on.
    d.rectangle([0, snap(960), SIZE, SIZE], fill=pal["ground"])
    d.rectangle([0, snap(960), SIZE, snap(960) + Z], fill=pal["ground_lit"])
    for x in range(0, SIZE, Z * 3):
        d.rectangle([x, snap(960) - Z * (1 + (x // Z) % 3), x + Z * 2, snap(960)],
                    fill=pal["ground_lit"])

    # 6. The glow.
    #
    #    Three versions to get here, and both failures were about STEP SIZE and TINT.
    #    Hard-edged ellipses looked like rings drawn on the sky. Dithering fixed the rings but
    #    used four big alpha steps and a cream tint, so it read as a grey smudge — cream over
    #    dark navy desaturates the sky rather than brightening it. What a pixel-art glow
    #    actually is: a fine ordered dither of a saturated tint, coverage falling off smoothly,
    #    moving the background toward the lantern and never away from it.
    if pal["glow_alpha"] > 0:
        px = icon.load()
        cx, cy, radius = 512.0, 600.0, 300.0
        gt = pal["glow"]
        for y in range(max(0, int(cy - radius)), min(SIZE, int(cy + radius))):
            for x in range(max(0, int(cx - radius)), min(SIZE, int(cx + radius))):
                t = 1.0 - (((x - cx) ** 2 + (y - cy) ** 2) ** 0.5) / radius
                if t <= 0:
                    continue
                lit = (t ** 1.6) * 16.0             # lit sub-cells out of 16
                whole, frac = int(lit), lit - int(lit)
                cover = (whole + (1 if (bayer(x, y) / 16.0) < frac else 0)) / 16.0
                a = cover * pal["glow_alpha"]
                if a <= 0.004:
                    continue
                sr, sg, sb = px[x, y]
                px[x, y] = (int(sr + (gt[0] - sr) * a),
                            int(sg + (gt[1] - sg) * a),
                            int(sb + (gt[2] - sb) * a))

    lan = lantern_sprite()
    if pal["lantern"] == "mono":
        lan = mono_lantern(lan)
    lan = lan.resize((lan.width * Z, lan.height * Z), Image.NEAREST)
    lx, ly = (SIZE - lan.width) // 2, snap(960) - lan.height
    icon.paste(lan, (lx, ly), lan)
    return icon, lan


def chroma(img):
    """The largest channel spread anywhere in the image. Zero means strictly gray."""
    px = img.convert("RGB").load()
    worst = 0
    for y in range(0, img.height, 3):
        for x in range(0, img.width, 3):
            r, g, b = px[x, y]
            worst = max(worst, max(r, g, b) - min(r, g, b))
    return worst


def main():
    for name, pal in (("light", LIGHT), ("dark", DARK), ("tinted", TINTED)):
        icon, lan = build(pal)
        icon.convert("RGB").save(f"{OUTDIR}/icon-{name}.png")   # iOS icons must be opaque
        note = ""
        if name == "tinted":
            sat = chroma(icon)
            note = (f"  chroma={sat} "
                    + ("OK strictly gray" if sat == 0 else "FAIL not gray"))
        print(f"{name:7} {icon.size[0]}x{icon.size[1]}  lantern {lan.width}x{lan.height} "
              f"at ({(SIZE - lan.width) // 2},{snap(960) - lan.height}){note}")
        icon.resize((180, 180), Image.LANCZOS).save(f"/tmp/mg-shots/icon-{name}-180.png")


if __name__ == "__main__":
    main()

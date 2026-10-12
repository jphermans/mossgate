#!/usr/bin/env python3
"""Build the Mossgate app icon out of the game's own art and palette.

The previous icon was a smooth vector coin — gradients and soft edges sitting next to a
game made entirely of chunky pixel sprites, and at 60pt on a home screen it read as a
camera lens. This composes the icon from assets the game already has: the pixel-art
lantern out of checkpoint.png, and sky colours sampled from a real in-game frame.

Everything is drawn on ONE pixel grid of ZxZ blocks. The sprite is scaled by that same
integer Z and the sky is drawn in Z-blocks, so nothing is ever half a pixel — which is
the whole difference between pixel art and a picture of pixel art.
"""

from PIL import Image, ImageDraw

SPRITE = "Resources/Sprites/checkpoint.png"
OUT = "Assets.xcassets/AppIcon.appiconset/icon-1024.png"

SIZE = 1024
Z = 6                     # the pixel size of the icon; everything snaps to ZxZ blocks

# --- palette, sampled from a real in-game frame ---
SKY_TOP = (5, 8, 38)
SKY_MID = (8, 14, 42)
SKY_LOW = (11, 20, 45)
SKY_TEAL = (14, 28, 48)
FIRS = (12, 24, 30)
GROUND = (48, 62, 21)
GROUND_LIT = (81, 103, 31)
MOON = (228, 213, 193)
MOON_SHADE = (150, 138, 122)
GLOW = (240, 160, 64)


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
        row = (y - y0) // Z
        t = row / max(1, cells - 1)
        for x in range(0, SIZE, Z):
            c = c1 if (bayer(x, y) / 16.0) < t else c0
            for dx in range(Z):
                for dy in range(Z):
                    if x + dx < SIZE and y + dy < SIZE:
                        px[x + dx, y + dy] = c


def main():
    icon = Image.new("RGB", (SIZE, SIZE), SKY_TOP)
    d = ImageDraw.Draw(icon)

    # 1. Sky. Dark navy at the top, warming to a teal glow near the horizon.
    band(icon, 0, 300, SKY_TOP, SKY_MID)
    band(icon, 300, 560, SKY_MID, SKY_LOW)
    band(icon, 560, 800, SKY_LOW, SKY_TEAL)
    band(icon, 800, 960, SKY_TEAL, SKY_LOW)

    # 2. Stars: single Z-cells, a few with a faint cross so they are not all identical.
    stars = [(60, 70), (150, 130), (250, 55), (350, 175), (860, 90), (930, 200),
             (80, 260), (200, 330), (900, 300), (820, 430), (120, 480), (960, 520),
             (55, 620), (170, 700), (880, 660), (940, 780), (300, 260), (420, 120),
             (560, 200), (660, 90), (740, 260), (30, 400), (990, 380), (620, 330)]
    for (x, y) in stars:
        d.rectangle([snap(x), snap(y), snap(x) + Z - 1, snap(y) + Z - 1], fill=MOON)
    for (x, y) in [(150, 130), (860, 90), (300, 260)]:
        d.rectangle([snap(x) - Z, snap(y), snap(x) - 1, snap(y) + Z - 1], fill=(150, 140, 126))
        d.rectangle([snap(x) + Z, snap(y), snap(x) + 2 * Z - 1, snap(y) + Z - 1], fill=(150, 140, 126))
        d.rectangle([snap(x), snap(y) + Z, snap(x) + Z - 1, snap(y) + 2 * Z - 1], fill=(150, 140, 126))

    # 3. Crescent moon, upper left, clear of the lantern so the two do not compete.
    mx, my, mr = snap(190), snap(170), snap(88)
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=MOON)
    d.ellipse([mx - mr + snap(48), my - mr - snap(22), mx + mr + snap(56), my + mr - snap(10)],
              fill=SKY_TOP)
    d.arc([mx - mr + snap(48), my - mr - snap(22), mx + mr + snap(56), my + mr - snap(10)],
          150, 250, fill=MOON_SHADE, width=Z)

    # 4. Distant firs, two steps off the sky so they read as far away rather than near.
    for base_x, peak, height in [(70, 985, 230), (330, 950, 300), (640, 975, 250),
                                 (900, 955, 290)]:
        half = height * 0.42
        d.polygon([(snap(base_x), snap(peak - height)), (snap(base_x - half), snap(peak)),
                   (snap(base_x + half), snap(peak))], fill=FIRS)

    # 5. Ground, with a lit top edge so the lantern has something to stand on.
    d.rectangle([0, snap(960), SIZE, SIZE], fill=GROUND)
    d.rectangle([0, snap(960), SIZE, snap(960) + Z], fill=GROUND_LIT)
    for x in range(0, SIZE, Z * 3):
        h = Z * (1 + (x // Z) % 3)
        d.rectangle([x, snap(960) - h, x + Z * 2, snap(960)], fill=GROUND_LIT)

    # 6. The glow.
    #
    #    Three versions to get here, and the two failures were both about STEP SIZE and
    #    TINT. Hard-edged ellipses looked like rings drawn on the sky. Dithering fixed the
    #    rings but used four big alpha steps and a cream tint, so it read as a grey smudge:
    #    cream over dark navy does not brighten the sky, it desaturates it.
    #
    #    What a pixel-art glow actually is: a fine ordered dither of a saturated orange, with
    #    the coverage falling off smoothly. Each pixel lights one of sixteen sub-cells by
    #    comparing the falloff against the Bayer threshold, so the gradient is made of
    #    pixels rather than of edges, and it only ever moves the sky toward the lantern.
    px = icon.load()
    cx, cy, radius = 512.0, 600.0, 300.0
    for y in range(max(0, int(cy - radius)), min(SIZE, int(cy + radius))):
        for x in range(max(0, int(cx - radius)), min(SIZE, int(cx + radius))):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            t = 1.0 - d / radius
            if t <= 0:
                continue
            lit = (t ** 1.6) * 16.0                 # lit sub-cells out of 16
            whole, frac = int(lit), lit - int(lit)
            cover = (whole + (1 if (bayer(x, y) / 16.0) < frac else 0)) / 16.0
            a = cover * 0.45
            if a <= 0.004:
                continue
            sr, sg, sb = px[x, y]
            px[x, y] = (int(sr + (255 - sr) * a),
                        int(sg + (152 - sg) * a),
                        int(sb + (52 - sb) * a))

    # 7. The lantern, from the game's own sprite, at an exact integer zoom.
    #
    #    Cropped to the lantern and not the whole sprite: the full sprite is a post with
    #    a lantern on it, which at any size that fits the frame leaves the lantern about
    #    7% of the icon's width and invisible at 60pt. The lantern alone is the game's
    #    own metaphor — "keep the lantern lit" — and at Z=5 it fills 40% of the width.
    sp = Image.open(SPRITE).convert("RGBA")
    w, h = sp.size
    # Find the lantern by its lit glass — the warm, bright pixels. The brass frame around
    # it is dark, and the post and the grass are not warm at all, so this picks out the
    # lantern and nothing else. Then grown by a margin so its frame and hook come with it.
    #
    # Cropping to the lantern and not the whole sprite is deliberate: the full sprite is a
    # post with a lantern on it, and at any size that fits the frame the lantern ends up
    # about 7% of the icon's width — invisible at 60pt. The lantern alone is the game's own
    # metaphor, "keep the lantern lit", and it fills twice that.
    src = sp.load()
    rows, cols = {}, {}
    for y in range(h):
        for x in range(int(w * 0.44), w):
            r, g, b, a = src[x, y]
            if a > 40 and r > 120 and r > b + 40 and g > 60:
                rows[y] = rows.get(y, 0) + 1
                cols[x] = cols.get(x, 0) + 1
    if not rows:
        raise SystemExit("no lantern found in the sprite — the warm-pixel test needs revisiting")

    # Keyed on DENSITY, not on the extremes. The lit glass is where warm pixels are many
    # per row; the handful at the top and bottom is the glow spilling onto the post's arm
    # and the grass. Counting those in made the crop 199px tall and pushed the lantern off
    # the top of the icon, which is exactly what happened on the first two attempts.
    # The post beside the lantern is lit by it, and its lit face has MORE warm pixels per
    # column than the glass does — so no density threshold separates the two, and raising
    # the threshold only pulled more post in. Split the histogram into runs instead and use
    # geometry: the lantern is the rightmost object, and its rows carry the most warm pixels.
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

    col_runs = runs_of(cols)
    row_runs = runs_of(rows)
    if not col_runs or not row_runs:
        raise SystemExit("no lantern found in the sprite — the warm-pixel test needs revisiting")
    left, right = col_runs[-1]                                  # rightmost object
    ty, by = max(row_runs, key=lambda r: sum(rows.get(y, 0) for y in range(r[0], r[1] + 1)))

    # Crop the top at the lantern's own cap. Cutting where the warm rows stop slices the
    # hanger in half and leaves a notch that reads as damage; following the silhouette up
    # from the glass until the object ends lands on the flat top of the cap, which looks
    # deliberate because it is the shape of the thing.
    glass_left, glass_right = max(0, left - 4), min(w, right + 5)
    cap_top = ty
    while cap_top > 0:
        row_has_solid = any(sp.getpixel((x, cap_top - 1))[3] > 40
                            for x in range(glass_left, glass_right))
        if not row_has_solid:
            break
        cap_top -= 1

    lantern = sp.crop((max(0, left - 20), max(0, cap_top - 1),
                       min(w, right + 21), min(h, by + 24)))

    # The sprites carry a magenta outline. At 1.6x against the game's dark backgrounds it
    # reads as a dark edge; at 6x it is a glaring pink fringe. Remapped to the dark brass of
    # the frame, so the silhouette it drew is kept and the pink is not.
    #
    # The test is blue-above-green, which is what makes magenta magenta: the lantern's own
    # glass is orange, where blue is far BELOW green, so a test this broad cannot touch it.
    px2 = lantern.load()
    remapped = 0
    for y in range(lantern.height):
        for x in range(lantern.width):
            r, g, b, a = px2[x, y]
            if a > 40 and b > g + 8 and r > 80:
                px2[x, y] = (54, 38, 28, a)
                remapped += 1
    print(f"  outline remapped: {remapped}px")
    lantern = lantern.resize((lantern.width * Z, lantern.height * Z), Image.NEAREST)

    lx = (SIZE - lantern.width) // 2
    ly = snap(960) - lantern.height            # standing on the ground line
    icon.paste(lantern, (lx, ly), lantern)

    final = icon.convert("RGB")                 # iOS icons must be fully opaque
    final.save(OUT)
    print(f"wrote {OUT}  {final.size[0]}x{final.size[1]}  Z={Z}")
    print(f"  lantern {lantern.width}x{lantern.height} at ({lx},{ly}) "
          f"= {100*lantern.width/SIZE:.0f}% wide, {100*lantern.height/SIZE:.0f}% tall")

    # Legibility at the sizes iOS actually uses.
    for size in (60, 120, 180):
        final.resize((size, size), Image.LANCZOS).save(f"/tmp/mg-shots/icon-{size}.png")
    print("  previews: /tmp/mg-shots/icon-{60,120,180}.png")


if __name__ == "__main__":
    main()

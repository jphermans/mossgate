"""Render a 30-second Mossgate promo video.

Frames at 30fps for 30s = 900 frames. We replay Wick Road (level 0) with
the player AI running through it autonomously (using the same physics
constants as the canvas engine), and overlay title + end cards.

Output: /tmp/promo_frames/  +  /tmp/mossgate-promo.mp4  (1920x1080, 30fps, H.264)

Run from mossgate-support:  python3 ../mossgate-main/scripts/render_promo.py
"""

import math
import os
import sys
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# ── Paths ─────────────────────────────────────────────────────────────
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPRITES = Path("/Users/jphermans/Development/mossgate-main/public/game")
OUT_DIR = Path("/tmp/promo_frames")
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_MP4 = Path("/tmp/mossgate-promo.mp4")

# ── Constants ────────────────────────────────────────────────────────
W, H = 1920, 1080
FPS = 30
DURATION = 30.0
TOTAL = int(FPS * DURATION)

# Camera scale: world is 720 wide, video is 1920 wide → 2.667x world, height ~360 → ~3x
WORLD_W = 720.0
WORLD_H = 360.0
SCALE = W / WORLD_W                # 2.667

# Title cards: 0..3s and 27..30s
TITLE_IN_END = 3.0
TITLE_OUT_START = 27.0

# ── Sprite cache ─────────────────────────────────────────────────────
random.seed(42)

class Cache:
    def __init__(self):
        self.idle = [Image.open(SPRITES / f"idle-{n}.png").convert("RGBA") for n in (1, 2, 3, 4)]
        self.run = [Image.open(SPRITES / f"run-{n}.png").convert("RGBA") for n in (1, 2, 3, 4)]
        self.jump = [Image.open(SPRITES / f"jump-{n}.png").convert("RGBA") for n in (1, 2, 3, 4)]
        self.coin = [Image.open(SPRITES / f"coin-{n}.png").convert("RGBA") for n in (1, 2, 3, 4)]
        self.flag = [Image.open(SPRITES / f"flag-{n}.png").convert("RGBA") for n in (1, 2, 3, 4)]
        self.spike = Image.open(SPRITES / "spike.png").convert("RGBA")
        self.checkpoint = Image.open(SPRITES / "checkpoint.png").convert("RGBA")
        self.block = Image.open(SPRITES / "block.png").convert("RGBA")
        self.ledge = Image.open(SPRITES / "ledge.png").convert("RGBA")
        for img in self.idle + self.run + self.jump + self.coin + self.flag:
            img.load()
        for img in (self.spike, self.checkpoint, self.block, self.ledge):
            img.load()

CACHE = Cache()

# ── Level 0 (Wick Road) data, copied from the original game ──────────
LEVEL_W = 3120.0
LEVEL_H = 760.0
SOLIDS = [
    (0,   512, 704, 240, False),
    (960, 512, 560, 240, False),
    (1600, 448, 190, 26, True),
    (1880, 384, 190, 26, True),
    (2160, 512, 960, 240, False),
]
MOVERS = [
    (740, 512, 170, 22, "x", 120, 3.3, 0),
]
COINS = [
    (180, 460), (300, 460), (430, 440), (560, 460),
    (820, 420), (910, 400), (1360, 450), (1688, 400),
    (1968, 332), (2400, 456), (2620, 440), (2840, 456),
]
SPIKES = [(1180, 478, 40, 34), (1340, 478, 40, 34)]
CHECKPOINTS = [(1040, 512)]
FLAG = (2980, 512)
SPAWN = (88, 512)

# ── Player AI ────────────────────────────────────────────────────────
PW, PH = 18, 32

class Player:
    def __init__(self):
        self.x = SPAWN[0] - PW / 2
        self.y = SPAWN[1] - PH
        self.vx = 0
        self.vy = 0
        self.facing = 1
        self.grounded = False
        self.coyote = 0
        self.extra_jumps = 1
        self.buffer = 0
        self.can_cut = False
        self.jump_age = 1

P = Player()
movers_pos = [(m[0], m[1]) for m in MOVERS]
movers_prev = list(movers_pos)
time_t = 0.0
got = set()
flag_reached = False

def place_movers():
    global movers_prev, movers_pos
    movers_prev = list(movers_pos)
    for i, m in enumerate(MOVERS):
        x, y, w, h, axis, dist, period, phase = m
        s = math.sin((time_t / period) * 2 * math.pi + phase)
        if axis == "x":
            movers_pos[i] = (x + s * dist + w/2, y + h/2)
        else:
            movers_pos[i] = (x + w/2, y + s * dist + h/2)

def collide_solid(prev_bottom):
    P.grounded = False
    for (sx, sy, sw, sh, oneway) in SOLIDS:
        if not oneway and rect_overlap(P.x, P.y, PW, PH, sx, sy, sw, sh):
            if P.vy >= 0 and prev_bottom <= sy + 4:
                P.y = sy - PH
                P.vy = 0
                P.grounded = True
            elif P.vy < 0 and P.y < sy + sh:
                P.y = sy + sh
                P.vy = 0
        elif oneway and P.vy >= 0 and prev_bottom <= sy + 6 and rect_overlap(P.x, P.y, PW, PH, sx, sy, sw, sh):
            P.y = sy - PH
            P.vy = 0
            P.grounded = True
    # Movers
    for i, (mx, my) in enumerate(movers_pos):
        mw2 = MOVERS[i][2]
        mh2 = MOVERS[i][3]
        if P.vy >= 0 and prev_bottom <= my + 6 and rect_overlap(P.x, P.y, PW, PH, mx - mw2/2, my - mh2/2, mw2, mh2):
            P.y = my - mh2/2 - PH
            P.vy = 0
            P.grounded = True
            # Move with mover
            dx = movers_pos[i][0] - movers_prev[i][0]
            P.x += dx

def rect_overlap(x, y, w, h, sx, sy, sw, sh):
    return x < sx + sw and x + w > sx and y < sy + sh and y + h > sy

def approach(v, target, delta):
    if v < target: return min(target, v + delta)
    if v > target: return max(target, v - delta)
    return target

def step(dt):
    global time_t
    time_t += dt
    place_movers()
    P.coyote = max(0, P.coyote - dt)
    P.buffer = max(0, P.buffer - dt)
    P.jump_age += dt

    # AI: hold right + jump over spikes + jump across platforms
    # Press right every frame.
    # Press jump when needed — simple policy.
    on_ground = P.grounded
    next_jump = False
    # Predict spike collision in next 60 px
    if on_ground:
        for (sx, sy, sw, sh) in SPIKES:
            feet_x = P.x + PW/2
            if sx - feet_x < 70 and sx > feet_x and P.y + PH > sy - 10:
                next_jump = True
                break
        # Jump to reach first odd-platform row
        # Levels: ground at y=512, first odd y=448 (over gap of width 256)
        # Detect ground edge ahead: find next solid to the right
        ahead = P.x + PW/2 + 80
        ground_below = 512
        for (sxx, syy, sw, sh, ow) in SOLIDS:
            if not ow and sxx <= ahead <= sxx + sw and syy >= P.y + PH - 10:
                ground_below = min(ground_below, syy)
        # If approaching a oneway platform above, jump
        for (sxx, syy, sw, sh, ow) in SOLIDS:
            if ow and sxx - (P.x + PW/2) < 90 and sxx > P.x + PW/2 and syy < P.y + PH:
                next_jump = True
                break
    if next_jump and on_ground:
        P.vy = -580
        P.can_cut = True
        P.coyote = 0
        P.extra_jumps = 1
        P.jump_age = 0
    # Double jump in air (for second spike)
    if not on_ground and P.vy > 100 and P.extra_jumps > 0:
        for (sx, sy, sw, sh) in SPIKES:
            feet_x = P.x + PW/2
            if sx - feet_x < 50 and sx > feet_x and abs((P.y + PH) - (sy + sh)) < 30:
                P.vy = -500
                P.extra_jumps = 0
                P.jump_age = 0
                break

    prev_bottom = P.y + PH
    P.vx = approach(P.vx, 255, 2800 * dt)  # always run right
    P.x += P.vx * dt
    # Wall collisions on solids
    for (sx, sy, sw, sh, ow) in SOLIDS:
        if not ow and rect_overlap(P.x, P.y, PW, PH, sx, sy, sw, sh):
            if P.vx > 0:
                P.x = sx - PW
                P.vx = 0

    P.vy = min(860, P.vy + (1400 if P.vy < 0 else 2900) * dt)
    P.y += P.vy * dt
    collide_solid(prev_bottom)
    if P.grounded:
        P.coyote = 0.11
        P.extra_jumps = 1
    # Spikes (promo only — for visual continuity we keep player alive through them)
    for (sx, sy, sw, sh) in SPIKES:
        # Promo mode: skip spike collisions so the player reaches the flag.
        # The spike is still drawn visually; just don't trigger die().
        pass
    # Coins
    feet_x = P.x + PW/2
    mid_y = P.y + PH*0.45
    for i, (cx, cy) in enumerate(COINS):
        if i in got: continue
        if math.hypot(feet_x - cx, mid_y - cy) < 40:
            got.add(i)
    # Flag
    fx, fy = FLAG
    if rect_overlap(P.x, P.y, PW, PH, fx - 18, fy - 84, 42, 84):
        global flag_reached
        flag_reached = True

# ── Frame composition ───────────────────────────────────────────────
def paint_sky(img, target, scroll):
    """Dusk gradient sky with stars and moon."""
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / H
        if t < 0.42:
            a = t / 0.42
            r = int(7 + (18-7)*a); g = int(20 + (56-20)*a); b = int(22 + (58-22)*a)
        elif t < 0.72:
            a = (t-0.42)/0.30
            r = int(18 + (28-18)*a); g = int(56 + (70-56)*a); b = int(58 + (54-58)*a)
        else:
            a = (t-0.72)/0.28
            r = int(28 + (13-28)*a); g = int(70 + (34-70)*a); b = int(54 + (28-54)*a)
        grad.putpixel((0, y), (r, g, b))
    grad = grad.resize((W, H))
    img.paste(grad, (0, 0))

    # Stars
    random.seed(99)
    for i in range(80):
        sx = ((i*137 + scroll*0.05) % W + W) % W
        sy = (i*73) % int(H*0.45)
        s = 1 if i % 3 else 2
        target.ellipse([sx, sy, sx+s, sy+s], fill=(244, 234, 212, 90 + (i%5)*20))

    # Moon
    moon_x = int(W * 0.82 - (scroll % 800) * 0.06)
    moon_y = int(H * 0.15)
    for r in range(80, 0, -2):
        a = int(80 * (1 - r/80))
        target.ellipse([moon_x - r, moon_y - r, moon_x + r, moon_y + r],
                       fill=(240, 160, 64, max(2, a // 4)))
    target.ellipse([moon_x - 32, moon_y - 32, moon_x + 32, moon_y + 32], fill=(244, 234, 212))
    target.ellipse([moon_x - 22, moon_y - 22, moon_x + 22, moon_y + 22], fill=(240, 160, 64))

    # Distant mountains (silhouettes)
    random.seed(7)
    for i in range(8):
        x = i * (W / 6) - 80
        bh = random.randint(80, 180)
        top = int(H * 0.62) - bh
        target.polygon([(x, int(H*0.62)),
                        (x + W*0.10, top),
                        (x + W*0.20, int(H*0.62))],
                       fill=(10, 30, 28))

def paint_hills(target, scroll):
    # Mid + near hills as sine waves
    for parallax, color, amp, base in [
        (0.15, (12, 36, 34), 26, H*0.62),
        (0.32, (16, 46, 42), 18, H*0.74),
    ]:
        target.polygon([(0, H)] + [
            (x, int(base + math.sin((x + scroll*parallax) * 0.012) * amp
                    + math.sin((x + scroll*parallax) * 0.004 + 2) * amp * 0.6))
            for x in range(0, W+1, 8)
        ] + [(W, H)], fill=color)

def composite_sprite(img, sx, sy, sw, sh, dx, dy, dw, dh, target_image):
    """Draw a sub-rect of a sprite onto an RGBA image at (dx, dy)."""
    cropped = img.crop((sx, sy, sx + sw, sy + sh))
    if dw != sw or dh != sh:
        cropped = cropped.resize((int(dw), int(dh)), Image.Resampling.NEAREST)
    target_image.alpha_composite(cropped, (int(dx), int(dy)))

def draw_world(img, target, cam_x, cam_y, t):
    # Hills (parallax)
    paint_hills(target, cam_x)

    # World offset: world (720 wide) scaled by SCALE → 1920 wide
    sx_off = -cam_x * SCALE
    sy_off = -cam_y * SCALE

    # Solids — stretch the block sprite to fill each solid (mimics original engine)
    for (x, y, w, h, oneway) in SOLIDS:
        tex = CACHE.ledge if oneway else CACHE.block
        dx = sx_off + x * SCALE
        dy = sy_off + y * SCALE
        dw = w * SCALE
        dh = h * SCALE
        # Tile horizontally to keep the texture crisp, but vertically stretch.
        tw = 48 * SCALE
        if oneway:
            composite_sprite(CACHE.ledge, 0, 0, CACHE.ledge.width, CACHE.ledge.height,
                             dx, dy, dw, dh, img)
        else:
            # Fill a horizontal strip by tiling block.png across, stretched vertically to fit
            num_h = max(1, int(h // 48) + 1)
            for i in range(int(dw / tw) + 2):
                tx = dx + i * tw
                # Tile vertically — multiple rows of the block texture to look like deep ground
                for j in range(num_h):
                    ty = dy + j * 48 * SCALE
                    th = 48 * SCALE
                    if j == num_h - 1:
                        # Last row — partial fill so we don't overshoot
                        th = dh - j * 48 * SCALE
                    composite_sprite(CACHE.block, 0, 0, CACHE.block.width, CACHE.block.height,
                                     tx, ty, tw + 1, th, img)

    # Movers (rendered as one-way ledges)
    for i, (mx, my) in enumerate(movers_pos):
        m = MOVERS[i]
        dx = sx_off + (movers_pos[i][0] - m[2]/2) * SCALE
        dy = sy_off + (movers_pos[i][1] - m[3]/2) * SCALE
        dw = m[2] * SCALE
        dh = m[3] * SCALE
        composite_sprite(CACHE.ledge, 0, 0, CACHE.ledge.width, CACHE.ledge.height,
                         dx, dy, dw, dh, img)

    # Spikes — draw as triangle (sprite is a full rock+spikes illustration, not useful scaled down)
    for (x, y, w, h) in SPIKES:
        dx = sx_off + x * SCALE
        dy = sy_off + y * SCALE
        dw = w * SCALE
        dh = h * SCALE
        # Draw 3 iron spikes as triangles on top of the ground
        ground_y = dy + dh
        for i in range(3):
            tx = dx + (i + 0.5) * (dw / 3)
            target.polygon([
                (tx - dw/8, ground_y),
                (tx, dy),
                (tx + dw/8, ground_y),
            ], fill=(140, 144, 150))
            # Amber highlight
            target.polygon([
                (tx - dw/12, ground_y - dh*0.4),
                (tx, dy + dh*0.2),
                (tx + dw/12, ground_y - dh*0.4),
            ], fill=(220, 180, 90))

    # Checkpoint
    for (x, y) in CHECKPOINTS:
        dx = sx_off + x * SCALE - 24 * SCALE
        dy = sy_off + y * SCALE - 36 * SCALE
        dw = 48 * SCALE
        dh = 72 * SCALE
        composite_sprite(CACHE.checkpoint, 0, 0, CACHE.checkpoint.width, CACHE.checkpoint.height,
                         dx, dy, dw, dh, img)

    # Coins
    frame = int(t * 8) % 4
    coin_tex = CACHE.coin[frame]
    for i, (x, y) in enumerate(COINS):
        if i in got: continue
        bob = math.sin(t * 3.2 + i) * 3
        dx = sx_off + x * SCALE - 13 * SCALE
        dy = sy_off + (y + bob) * SCALE - 13 * SCALE
        dw = 26 * SCALE
        dh = 26 * SCALE
        composite_sprite(coin_tex, 0, 0, coin_tex.width, coin_tex.height, dx, dy, dw, dh, img)

    # Flag
    frame = int(t * 6) % 4
    flag_tex = CACHE.flag[frame]
    fx, fy = FLAG
    dx = sx_off + fx * SCALE - 21 * SCALE
    dy = sy_off + fy * SCALE - 46 * SCALE
    dw = 42 * SCALE
    dh = 92 * SCALE
    composite_sprite(flag_tex, 0, 0, flag_tex.width, flag_tex.height, dx, dy, dw, dh, img)

    # Player
    ptex = CACHE.idle[0]
    if not P.grounded and P.vy < -100:
        ptex = CACHE.jump[1]
    elif not P.grounded:
        ptex = CACHE.jump[3]
    elif abs(P.vx) > 28:
        ptex = CACHE.run[int(t * 10) % 4]
    else:
        ptex = CACHE.idle[int(t * 5) % 4]
    dx = sx_off + P.x * SCALE
    dy = sy_off + P.y * SCALE
    dw = PW * SCALE * 1.6
    dh = PH * SCALE * 1.6
    # Offset so player center is at feet_x
    dx -= (dw - PW * SCALE) / 2
    # Flip horizontally if facing left
    if P.facing < 0:
        cropped = ptex.crop((0, 0, ptex.width, ptex.height)).resize(
            (int(dw), int(dh)), Image.Resampling.NEAREST
        ).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        img.alpha_composite(cropped, (int(dx), int(dy)))
    else:
        composite_sprite(ptex, 0, 0, ptex.width, ptex.height, dx, dy, dw, dh, img)

def draw_hud(img, target, t):
    # Coin counter pill (top-left)
    pill_w, pill_h = 280, 64
    px, py = 32, 32
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle([px, py, px + pill_w, py + pill_h], radius=32,
                         fill=(20, 48, 44, 200), outline=(44, 74, 66), width=2)
    od.ellipse([px+18, py+18, px+44, py+44], fill=(240, 160, 64))
    od.text((px+58, py+18), f"{len(got)} / {len(COINS)}",
            fill=(244, 234, 212))
    img.alpha_composite(overlay)

    # Title (top center)
    overlay2 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od2 = ImageDraw.Draw(overlay2)
    try:
        from PIL import ImageFont
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        f_lg = ImageFont.truetype(font_path, 36)
        f_sm = ImageFont.truetype(font_path, 18)
    except Exception:
        f_lg = f_sm = None
    od2.text((W//2 - 100, py + 18), "Wick Road", fill=(244, 234, 212), font=f_lg)
    img.alpha_composite(overlay2)

def draw_title_card(img, target, t, fade_in):
    """t in seconds; fade_in: 0..1."""
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    try:
        from PIL import ImageFont
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        f_huge = ImageFont.truetype(font_path, 220)
        f_med = ImageFont.truetype(font_path, 60)
        f_small = ImageFont.truetype(font_path, 28)
    except Exception:
        f_huge = f_med = f_small = None

    # Eyebrow
    od.text((W//2 - 240, H//2 - 240), "DUSK RUINS", fill=(240, 160, 64, int(255*fade_in)),
            font=f_med)
    # Title
    od.text((W//2 - 360, H//2 - 150), "Mossgate", fill=(244, 234, 212, int(255*fade_in)),
            font=f_huge)
    # Subtitle
    od.text((W//2 - 230, H//2 + 80), "a JPHsystems game", fill=(155, 181, 168, int(255*fade_in)),
            font=f_small)
    # Lantern (small)
    cx, cy = W//2, H//2 + 200
    for r in range(120, 0, -2):
        a = int(80 * (1 - r/120) * fade_in)
        od.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(240, 160, 64, max(2, a//4)))
    od.ellipse([cx-44, cy-44, cx+44, cy+44], fill=(196, 106, 50, int(255*fade_in)))
    od.ellipse([cx-30, cy-30, cx+30, cy+30], fill=(240, 160, 64, int(255*fade_in)))
    od.ellipse([cx-14, cy-14, cx+14, cy+14], fill=(244, 234, 212, int(255*fade_in)))
    img.alpha_composite(overlay)

def draw_end_card(img, target, t, fade_in):
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    try:
        from PIL import ImageFont
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        f_huge = ImageFont.truetype(font_path, 180)
        f_med = ImageFont.truetype(font_path, 48)
        f_small = ImageFont.truetype(font_path, 26)
    except Exception:
        f_huge = f_med = f_small = None

    # Subtle dark scrim
    od.rectangle([0, 0, W, H], fill=(7, 20, 22, int(220*fade_in)))

    # "Available now"
    od.text((W//2 - 280, H//2 - 200), "Available now", fill=(244, 234, 212, int(255*fade_in)),
            font=f_med)
    # "Mossgate"
    od.text((W//2 - 280, H//2 - 100), "Mossgate", fill=(244, 234, 212, int(255*fade_in)),
            font=f_huge)

    # App Store badge (simplified)
    bx, by, bw, bh = W//2 - 180, H//2 + 80, 360, 110
    od.rounded_rectangle([bx, by, bx+bw, by+bh], radius=16,
                         fill=(0, 0, 0, int(255*fade_in)),
                         outline=(40, 40, 40), width=2)
    od.text((bx+24, by+22), "Download on the", fill=(255, 255, 255, int(220*fade_in)),
            font=f_small)
    od.text((bx+24, by+58), "App Store", fill=(255, 255, 255, int(255*fade_in)),
            font=f_med)

    # JPHsystems credit
    od.text((W//2 - 110, H - 100), "Made by JPHsystems", fill=(155, 181, 168, int(220*fade_in)),
            font=f_small)
    img.alpha_composite(overlay)

# ── Render ───────────────────────────────────────────────────────────
def main():
    print(f"Rendering {TOTAL} frames at {W}x{H} ({FPS}fps, {DURATION:.0f}s)...")
    for f in range(TOTAL):
        t = f / FPS
        # Camera follows player
        cam_x = clamp(P.x + PW/2 - 360, 0, max(0, LEVEL_W - WORLD_W))
        # Match the original canvas engine: player at 70% screen height
        cam_y = clamp(P.y - WORLD_H * 0.45 + PH/2, 0, max(0, LEVEL_H - WORLD_H))

        img = Image.new("RGBA", (W, H), (12, 28, 31, 255))
        target = ImageDraw.Draw(img)
        paint_sky(img, target, cam_x)
        draw_world(img, target, cam_x, cam_y, t)

        # HUD overlay (only during gameplay segment)
        if TITLE_IN_END <= t < TITLE_OUT_START:
            draw_hud(img, target, t)

        # Title card 0..3s — solid for 2s, then fade out
        if t < 2.0:
            draw_title_card(img, target, t, 1.0)
        elif t < TITLE_IN_END:
            fade = max(0.0, 1.0 - (t - 2.0) / 1.0)
            draw_title_card(img, target, t, fade)
        # End card 27..30s
        elif t < 28.5:
            fade = min(1.0, (t - TITLE_OUT_START) / 1.0)
            draw_end_card(img, target, t, fade)
        else:
            draw_end_card(img, target, t, 1.0)

        # Soft vignette
        vig = Image.new("L", (W, H), 0)
        vd = ImageDraw.Draw(vig)
        for i in range(40):
            a = int((i / 40) * 100)
            vd.rectangle([i*8, i*8, W - i*8, H - i*8], outline=a, width=2)
        # (skip for speed — vignette is nice but slow)

        img.convert("RGB").save(OUT_DIR / f"frame_{f:05d}.jpg", "JPEG", quality=88)

        # Step physics
        if t < TITLE_OUT_START:
            step(1/30)
        else:
            # After end card starts, freeze (or slow down)
            pass

        if f % 30 == 0:
            print(f"  frame {f}/{TOTAL}  t={t:.1f}s  cam_x={cam_x:.0f}  flag={flag_reached}")

    print("Done. Encoding with ffmpeg...")
    import subprocess
    subprocess.run([
        "ffmpeg", "-y",
        "-framerate", str(FPS),
        "-i", str(OUT_DIR / "frame_%05d.jpg"),
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "20",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        str(OUT_MP4)
    ], check=True)
    print(f"Wrote {OUT_MP4} ({OUT_MP4.stat().st_size // 1024} KB)")

def clamp(v, a, b):
    return max(a, min(b, v))

if __name__ == "__main__":
    main()
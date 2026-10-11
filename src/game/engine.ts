import { previewPathPrefix } from "@/lib/preview-path-prefix";
import { Sfx } from "@/game/audio";
import { LEVELS, type Level, type MoverDef, type Rect, type Solid } from "@/game/levels";

export type Phase = "title" | "play" | "pause" | "dead" | "win";

export type Hud = {
  phase: Phase;
  level: number;
  name: string;
  coins: number;
  total: number;
  checkpoint: boolean;
  jumps: number;
  hint: string;
  cleared: boolean[];
  best: number[];
};

type TouchState = { left: boolean; right: boolean; jump: boolean; down: boolean; drop: boolean };

type Mover = MoverDef & { px: number; py: number; prevX: number; prevY: number };

type Sprite = {
  img: HTMLImageElement;
  sx: number;
  sy: number;
  sw: number;
  sh: number;
  foot: number;
};

type Particle = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  max: number;
  size: number;
  color: string;
};

type Snapshot = { x: number; y: number; coins: number[]; cp: number };

const PW = 18;
const PH = 32;
const RUN = 255;
const ACCEL_G = 2800;
const ACCEL_A = 1650;
const FRIC = 2400;
const JUMP_V = 580;
const DJUMP_V = 500;
const G_RISE = 1400;
const G_FALL = 2900;
const G_APEX = 760;
const APEX = 100;
const MAX_FALL = 860;
const COYOTE = 0.11;
const BUFFER = 0.13;
const SAVE_KEY = "mossgate-save-v1";

const GAME_KEYS = new Set([
  "ArrowLeft",
  "ArrowRight",
  "ArrowUp",
  "ArrowDown",
  "KeyA",
  "KeyD",
  "KeyW",
  "KeyS",
  "Space",
  "Escape",
]);

function assetUrl(file: string) {
  const prefix = previewPathPrefix(window.location.hostname, window.location.pathname) ?? "";
  return `${prefix}/game/${file}`;
}

function approach(value: number, target: number, delta: number) {
  if (value < target) return Math.min(target, value + delta);
  if (value > target) return Math.max(target, value - delta);
  return target;
}

function clamp(v: number, a: number, b: number) {
  return Math.max(a, Math.min(b, v));
}

function overlaps(x: number, y: number, w: number, h: number, b: Rect) {
  return x < b.x + b.w && x + w > b.x && y < b.y + b.h && y + h > b.y;
}

function loadSave(): { cleared: boolean[]; best: number[] } {
  const empty = { cleared: [false, false, false], best: [0, 0, 0] };
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return empty;
    const parsed = JSON.parse(raw) as { cleared?: boolean[]; best?: number[] };
    return {
      cleared: [0, 1, 2].map((i) => Boolean(parsed.cleared?.[i])),
      best: [0, 1, 2].map((i) => Number(parsed.best?.[i]) || 0),
    };
  } catch {
    return empty;
  }
}

function writeSave(cleared: boolean[], best: number[]) {
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify({ v: 1, cleared, best }));
  } catch {
    /* ignore quota */
  }
}

async function loadSprite(file: string): Promise<Sprite | null> {
  const img = await new Promise<HTMLImageElement | null>((resolve) => {
    const el = new Image();
    el.crossOrigin = "anonymous";
    el.onload = () => resolve(el);
    el.onerror = () => resolve(null);
    el.src = assetUrl(file);
  });
  if (!img) return null;
  const canvas = document.createElement("canvas");
  canvas.width = img.width;
  canvas.height = img.height;
  const g = canvas.getContext("2d");
  if (!g) return null;
  g.drawImage(img, 0, 0);
  const data = g.getImageData(0, 0, img.width, img.height).data;
  let minX = img.width;
  let minY = img.height;
  let maxX = 0;
  let maxY = 0;
  let foot = 0;
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      if (data[(y * img.width + x) * 4 + 3]! > 24) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        foot = y;
      }
    }
  }
  if (maxX <= minX || maxY <= minY) return null;
  return { img, sx: minX, sy: minY, sw: maxX - minX + 1, sh: maxY - minY + 1, foot };
}

export type GameApi = {
  start: (level: number) => void;
  respawn: () => void;
  retry: () => void;
  pause: () => void;
  resume: () => void;
  title: () => void;
  setTouch: (key: keyof TouchState, down: boolean) => void;
  unlock: () => void;
  destroy: () => void;
};

export function createGame(canvas: HTMLCanvasElement, onHud: (hud: Hud) => void): GameApi {
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas unsupported");
  const sfx = new Sfx();
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const keys = new Set<string>();
  const injected = new Set<string>();
  let padX = 0;
  let padJump = false;
  let steer = 0;
  const touch: TouchState = { left: false, right: false, jump: false, down: false, drop: false };
  let prevJump = false;

  let levelIndex = 0;
  let level: Level = LEVELS[0]!;
  let movers: Mover[] = [];
  let got = new Set<number>();
  let cp = -1;
  let snap: Snapshot = { x: 0, y: 0, coins: [], cp: -1 };
  let phase: Phase = "title";
  const save = loadSave();

  const player = { x: 0, y: 0, vx: 0, vy: 0, facing: 1 };
  let grounded = false;
  let groundKind: "none" | "solid" | "oneway" | "mover" = "none";
  let ride = -1;
  let coyote = 0;
  let extra = 1;
  let buffer = 0;
  let canCut = false;
  let drop = 0;
  let grace = 0;
  let jumpAge = 1;
  let squash = 0;
  let wasGrounded = false;
  let time = 0;
  let acc = 0;
  let trauma = 0;
  let camX = 0;
  let camY = 0;
  const view = { w: 720, h: 420, ox: 0, oy: 0 };
  let hint = "";
  let sawRun = false;
  let sawDouble = false;
  let sawRide = false;
  const particles: Particle[] = [];

  let sheets: {
    idle: Sprite[];
    run: Sprite[];
    jump: Sprite[];
    coin: Sprite[];
    flag: Sprite[];
    spike: Sprite | null;
    post: Sprite | null;
    block: Sprite | null;
    ledge: Sprite | null;
  } = { idle: [], run: [], jump: [], coin: [], flag: [], spike: null, post: null, block: null, ledge: null };

  let raf = 0;
  let last = performance.now();
  let hudSig = "";

  function buzz(ms: number) {
    if (reduce) return;
    navigator.vibrate?.(ms);
  }

  function lesson() {
    if (phase !== "play") return "";
    if (!sawRun) {
      if (Math.abs(player.vx) > 40) sawRun = true;
      else if (levelIndex === 0) return "Hold right";
    }
    if (levelIndex === 0 && !sawRide) {
      if (ride >= 0) sawRide = true;
      else if (player.x > 500 && player.x < 820) return "Step onto the stone";
    }
    if (levelIndex === 0 && grounded) {
      for (const sp of level.spikes) {
        if (sp.x > player.x + 8 && sp.x < player.x + 120 && player.y + PH > sp.y - 8) return "Jump the iron";
      }
    }
    if (!sawDouble && !grounded && extra > 0 && jumpAge > 0.12) return "Jump again";
    return "";
  }

  function burst(x: number, y: number, n: number, color: string, speed: number) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = speed * (0.35 + Math.random());
      particles.push({
        x,
        y,
        vx: Math.cos(a) * s,
        vy: Math.sin(a) * s - speed * 0.35,
        life: 0.28 + Math.random() * 0.28,
        max: 0.5,
        size: 1.6 + Math.random() * 2.2,
        color,
      });
    }
    if (particles.length > 140) particles.splice(0, particles.length - 140);
  }

  function emit() {
    const hud: Hud = {
      phase,
      level: levelIndex,
      name: level.name,
      coins: got.size,
      total: level.coins.length,
      checkpoint: cp >= 0,
      jumps: grounded || coyote > 0 ? 2 : extra > 0 ? 1 : 0,
      hint,
      cleared: save.cleared,
      best: save.best,
    };
    const sig = `${hud.phase}|${hud.level}|${hud.coins}|${hud.total}|${hud.checkpoint}|${hud.jumps}|${hud.hint}|${hud.cleared.join("")}|${hud.best.join(",")}`;
    if (sig !== hudSig) {
      hudSig = sig;
      onHud(hud);
    }
  }

  function placePlayer(feetX: number, feetY: number) {
    player.x = feetX - PW / 2;
    player.y = feetY - PH;
    player.vx = 0;
    player.vy = 0;
    grounded = true;
    groundKind = "solid";
    wasGrounded = true;
    ride = -1;
    coyote = COYOTE;
    extra = 1;
    canCut = false;
    jumpAge = 1;
    grace = 0.25;
  }

  function placeMovers(t: number) {
    for (const m of movers) {
      m.prevX = m.px;
      m.prevY = m.py;
      const s = Math.sin((t / m.period) * Math.PI * 2 + m.phase);
      m.px = m.axis === "x" ? m.x + s * m.distance : m.x;
      m.py = m.axis === "y" ? m.y + s * m.distance : m.y;
    }
  }

  function loadLevel(index: number, next: Phase) {
    levelIndex = index;
    level = LEVELS[index] ?? LEVELS[0]!;
    movers = level.movers.map((m) => ({ ...m, px: m.x, py: m.y, prevX: m.x, prevY: m.y }));
    got = new Set();
    cp = -1;
    snap = { x: level.spawn.x, y: level.spawn.y, coins: [], cp: -1 };
    time = 0;
    acc = 0;
    placeMovers(0);
    for (const m of movers) {
      m.prevX = m.px;
      m.prevY = m.py;
    }
    placePlayer(level.spawn.x, level.spawn.y);
    player.facing = 1;
    squash = 0;
    sawRun = false;
    sawRide = false;
    hint = "";
    phase = next;
    camX = clamp(level.spawn.x - 180, 0, Math.max(0, level.width - view.w));
    camY = clamp(level.spawn.y - view.h * 0.72, 0, Math.max(0, level.height - view.h));
    emit();
  }

  function doJump(power: number, double: boolean) {
    player.vy = -power;
    grounded = false;
    groundKind = "none";
    ride = -1;
    canCut = true;
    jumpAge = 0;
    coyote = 0;
    sfx.jump(double);
    if (double) sawDouble = true;
    buzz(double ? 16 : 10);
    burst(player.x + PW / 2, player.y + PH, double ? 10 : 6, double ? "#f4ead4" : "#f0a040", double ? 90 : 60);
    if (!reduce) trauma = Math.min(1, trauma + (double ? 0.18 : 0.1));
  }

  function tryDrop() {
    if (!touch.drop) return;
    touch.drop = false;
    if (grounded && (groundKind === "oneway" || groundKind === "mover")) {
      drop = 0.18;
      grounded = false;
      groundKind = "none";
      ride = -1;
      coyote = 0;
      player.y += 4;
      buffer = 0;
    }
  }

  function tryJump() {
    if (buffer <= 0) return false;
    if (touch.down || held("KeyS") || held("ArrowDown")) {
      if (grounded && (groundKind === "oneway" || groundKind === "mover")) {
        drop = 0.18;
        grounded = false;
        groundKind = "none";
        ride = -1;
        coyote = 0;
        player.y += 4;
        buffer = 0;
        return true;
      }
    }
    if (coyote > 0) {
      doJump(JUMP_V, false);
      extra = 1;
      buffer = 0;
      return true;
    }
    if (!grounded && extra > 0) {
      doJump(DJUMP_V, true);
      extra = 0;
      buffer = 0;
      return true;
    }
    return false;
  }

  function die() {
    if (phase !== "play") return;
    phase = "dead";
    sfx.die();
    buzz(36);
    trauma = Math.min(1, trauma + 0.75);
    burst(player.x + PW / 2, player.y + PH / 2, 18, "#f0a040", 140);
    burst(player.x + PW / 2, player.y + 8, 8, "#f4ead4", 80);
    emit();
  }

  function win() {
    if (phase !== "play") return;
    phase = "win";
    sfx.win();
    buzz(28);
    trauma = Math.min(1, trauma + 0.35);
    burst(level.flag.x, level.flag.y - 40, 22, "#f0a040", 120);
    save.cleared[levelIndex] = true;
    save.best[levelIndex] = Math.max(save.best[levelIndex] ?? 0, got.size);
    writeSave(save.cleared, save.best);
    emit();
  }

  function held(code: string) {
    return keys.has(code) || injected.has(code);
  }

  function moveX() {
    let x = 0;
    if (held("KeyA") || held("ArrowLeft") || touch.left) x -= 1;
    if (held("KeyD") || held("ArrowRight") || touch.right) x += 1;
    x += padX;
    x -= steer;
    return clamp(x, -1, 1);
  }

  function step(dt: number) {
    time += dt;
    placeMovers(time);
    grace = Math.max(0, grace - dt);
    drop = Math.max(0, drop - dt);
    buffer = Math.max(0, buffer - dt);
    jumpAge += dt;

    const jumpDown = held("Space") || held("KeyW") || held("ArrowUp") || touch.jump || padJump;
    if (jumpDown && !prevJump) buffer = BUFFER;
    const released = prevJump && !jumpDown;
    prevJump = jumpDown;

    if (released && player.vy < 0 && canCut) {
      player.vy *= 0.48;
      canCut = false;
    }

    tryDrop();
    tryJump();

    if (ride >= 0 && grounded) {
      const m = movers[ride];
      if (m) {
        player.x += m.px - m.prevX;
        player.y = m.py - PH;
        player.vy = 0;
      }
    }

    const dir = moveX();
    if (dir < 0) player.facing = -1;
    else if (dir > 0) player.facing = 1;
    const accel = grounded ? ACCEL_G : ACCEL_A;
    player.vx = approach(player.vx, dir * RUN, accel * dt);
    if (dir === 0 && grounded) player.vx = approach(player.vx, 0, FRIC * dt);

    player.x += player.vx * dt;
    for (const s of level.solids) {
      if (s.oneway) continue;
      if (!overlaps(player.x, player.y, PW, PH, s)) continue;
      if (player.vx > 0) player.x = s.x - PW;
      else if (player.vx < 0) player.x = s.x + s.w;
      else if (player.x + PW / 2 < s.x + s.w / 2) player.x = s.x - PW;
      else player.x = s.x + s.w;
      player.vx = 0;
    }

    const prevBottom = player.y + PH;
    let g = player.vy < 0 ? G_RISE : G_FALL;
    if (Math.abs(player.vy) < APEX) g = G_APEX;
    player.vy = Math.min(MAX_FALL, player.vy + g * dt);
    player.y += player.vy * dt;

    grounded = false;
    groundKind = "none";
    ride = -1;

    for (const s of level.solids) {
      if (s.oneway) continue;
      if (!overlaps(player.x, player.y, PW, PH, s)) continue;
      if (player.vy >= 0 && prevBottom <= s.y + 4) {
        player.y = s.y - PH;
        player.vy = 0;
        grounded = true;
        groundKind = "solid";
      } else if (player.vy < 0 && player.y < s.y + s.h) {
        player.y = s.y + s.h;
        player.vy = 0;
      }
    }

    const pads: { rect: Rect; kind: "oneway" | "mover"; id: number }[] = [];
    level.solids.forEach((s, i) => {
      if (s.oneway) pads.push({ rect: s, kind: "oneway", id: i });
    });
    movers.forEach((m, i) => {
      pads.push({ rect: { x: m.px, y: m.py, w: m.w, h: m.h }, kind: "mover", id: i });
    });

    if (drop <= 0 && player.vy >= 0) {
      for (const pad of pads) {
        const r = pad.rect;
        if (prevBottom > r.y + 6) continue;
        if (!overlaps(player.x, player.y, PW, PH, r)) continue;
        player.y = r.y - PH;
        player.vy = 0;
        grounded = true;
        groundKind = pad.kind;
        if (pad.kind === "mover") ride = pad.id;
      }
    }

    if (grounded) {
      coyote = COYOTE;
      extra = 1;
    } else {
      coyote = Math.max(0, coyote - dt);
    }

    if (grounded && !wasGrounded) {
      squash = 1;
      sfx.land();
      burst(player.x + PW / 2, player.y + PH, 5, "#9bb5a8", 40);
      if (!reduce) trauma = Math.min(1, trauma + 0.12);
    }
    wasGrounded = grounded;
    tryJump();

    if (grace <= 0) {
      const body = { x: player.x + 3, y: player.y + 4, w: PW - 6, h: PH - 6 };
      for (const sp of level.spikes) {
        if (overlaps(body.x, body.y, body.w, body.h, sp)) {
          die();
          return;
        }
      }
      if (player.y > level.killY) {
        die();
        return;
      }
    }

    const feetX = player.x + PW / 2;
    const midY = player.y + PH * 0.45;
    level.coins.forEach((c, i) => {
      if (got.has(i)) return;
      if (Math.hypot(feetX - c.x, midY - c.y) < 40) {
        got.add(i);
        sfx.coin();
        buzz(12);
        burst(c.x, c.y, 8, "#f0a040", 70);
        emit();
      }
    });

    level.checkpoints.forEach((c, i) => {
      if (i <= cp) return;
      const rect = { x: c.x - 24, y: c.y - 72, w: 48, h: 72 };
      if (overlaps(player.x, player.y, PW, PH, rect)) {
        cp = i;
        snap = { x: c.x, y: c.y, coins: [...got], cp };
        sfx.checkpoint();
        buzz(20);
        burst(c.x, c.y - 48, 12, "#f0a040", 80);
        if (!reduce) trauma = Math.min(1, trauma + 0.16);
        emit();
      }
    });

    const flag = { x: level.flag.x - 18, y: level.flag.y - 84, w: 42, h: 84 };
    if (overlaps(player.x, player.y, PW, PH, flag)) win();

    if (grounded && Math.abs(player.vx) > 80 && Math.random() < 8 * dt) {
      burst(player.x + PW / 2, player.y + PH, 1, "#9bb5a8", 24);
    }
    hint = lesson();
    emit();
  }

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const rect = canvas.getBoundingClientRect();
    const w = Math.max(1, Math.floor(rect.width * dpr));
    const h = Math.max(1, Math.floor(rect.height * dpr));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    const aspect = w / Math.max(1, h);
    if (aspect >= 1) {
      view.w = clamp(440 * aspect, 640, 920);
      view.h = view.w / aspect;
      view.ox = 0;
      view.oy = 0;
    } else {
      view.w = 280;
      const fit = w / view.w;
      view.h = clamp(Math.round(h * 0.68) / fit, 210, 320);
      view.ox = 0;
      view.oy = Math.max(0, h - view.h * fit);
    }
  }

  function updateCamera(dt: number) {
    const narrow = view.w < 560;
    const focusX = player.x + PW / 2 + player.facing * (narrow ? 78 : 36);
    const focusY = player.y + PH * 0.42;
    const left = view.w * (player.facing >= 0 ? (narrow ? 0.22 : 0.36) : narrow ? 0.46 : 0.36);
    const right = view.w * (player.facing >= 0 ? (narrow ? 0.72 : 0.56) : narrow ? 0.52 : 0.56);
    const top = view.h * (narrow ? 0.4 : 0.38);
    const bottom = view.h * 0.66;
    let desiredX = camX;
    let desiredY = camY;
    const sx = focusX - camX;
    const sy = focusY - camY;
    if (sx < left) desiredX = focusX - left;
    else if (sx > right) desiredX = focusX - right;
    if (sy < top) desiredY = focusY - top;
    else if (sy > bottom) desiredY = focusY - bottom;
    const k = 1 - Math.exp(-7 * dt);
    camX += (desiredX - camX) * k;
    camY += (desiredY - camY) * k;
    camX = clamp(camX, 0, Math.max(0, level.width - view.w));
    camY = clamp(camY, 0, Math.max(0, level.height - view.h));
    trauma = Math.max(0, trauma - dt * 1.5);
  }

  function drawImageRect(sp: Sprite | null, x: number, y: number, w: number, h: number, inset = 0) {
    if (!sp) return false;
    const sx = sp.sx + sp.sw * inset;
    const sy = sp.sy + sp.sh * inset;
    const sw = sp.sw * (1 - inset * 2);
    const sh = sp.sh * (1 - inset * 2);
    ctx!.drawImage(sp.img, sx, sy, sw, sh, x, y, w, h);
    return true;
  }

  function drawFeet(sp: Sprite | null, feetX: number, feetY: number, destH: number, flip = false) {
    if (!sp) return false;
    const destW = destH * (sp.sw / sp.sh);
    const footFromTop = ((sp.foot - sp.sy) / sp.sh) * destH;
    ctx!.save();
    ctx!.translate(feetX, feetY);
    ctx!.scale(flip ? -1 : 1, 1);
    ctx!.drawImage(sp.img, sp.sx, sp.sy, sp.sw, sp.sh, -destW / 2, -footFromTop, destW, destH);
    ctx!.restore();
    return true;
  }

  function paintSky(scroll: number, scale: number) {
    const w = canvas.width;
    const h = canvas.height;
    const sky = ctx!.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, "#071416");
    sky.addColorStop(0.42, "#12383a");
    sky.addColorStop(0.72, "#1c4636");
    sky.addColorStop(1, "#0d221c");
    ctx!.fillStyle = sky;
    ctx!.fillRect(0, 0, w, h);

    ctx!.fillStyle = "#f4ead4";
    for (let i = 0; i < 32; i++) {
      const sx = ((i * 97 + scroll * 0.08) % w + w) % w;
      const sy = (i * 53) % (h * 0.46);
      ctx!.globalAlpha = 0.22 + (i % 5) * 0.08;
      const s = (i % 4 === 0 ? 2 : 1.2) * Math.max(1, scale * 0.35);
      ctx!.fillRect(sx, sy, s, s);
    }
    ctx!.globalAlpha = 1;

    const moonX = w * 0.78 - (scroll % 800) * 0.08;
    const moonY = h * 0.13;
    const moonR = 54 * Math.max(1, scale * 0.55);
    const glow = ctx!.createRadialGradient(moonX, moonY, moonR * 0.2, moonX, moonY, moonR * 2.4);
    glow.addColorStop(0, "rgba(244,234,212,0.92)");
    glow.addColorStop(0.35, "rgba(240,160,64,0.16)");
    glow.addColorStop(1, "rgba(240,160,64,0)");
    ctx!.fillStyle = glow;
    ctx!.beginPath();
    ctx!.arc(moonX, moonY, moonR * 2.4, 0, Math.PI * 2);
    ctx!.fill();

    ctx!.fillStyle = "#0a1e1c";
    for (let i = 0; i < 6; i++) {
      const span = w + 160 * scale;
      const x = ((i * span * 0.22 - scroll * 0.12) % span + span) % span - 40 * scale;
      const bh = (46 + (i % 3) * 22) * Math.max(1, scale * 0.45);
      const top = h * 0.34 - bh;
      ctx!.fillRect(x, top, 18 * scale, bh);
      ctx!.beginPath();
      ctx!.moveTo(x - 4 * scale, top + 8 * scale);
      ctx!.lineTo(x + 9 * scale, top - 16 * scale);
      ctx!.lineTo(x + 22 * scale, top + 8 * scale);
      ctx!.fill();
    }

    ctx!.fillStyle = "#f0a040";
    for (let i = 0; i < 7; i++) {
      const fx = ((i * 140 + Math.sin(time * 0.7 + i) * 24) % w + w) % w;
      const fy = h * (0.18 + (i % 4) * 0.06) + Math.cos(time * 0.9 + i) * 8;
      ctx!.globalAlpha = 0.25 + (Math.sin(time * 2 + i) * 0.5 + 0.5) * 0.45;
      ctx!.beginPath();
      ctx!.arc(fx, fy, 1.6 * Math.max(1, scale * 0.4), 0, Math.PI * 2);
      ctx!.fill();
    }
    ctx!.globalAlpha = 1;
  }

  function render(dt: number) {
    resize();
    updateCamera(dt);
    const shake = reduce ? 0 : trauma * trauma;
    const shakeX = (Math.sin(time * 47) * 0.5 + Math.sin(time * 23) * 0.5) * 10 * shake;
    const shakeY = (Math.cos(time * 41) * 0.5 + Math.sin(time * 19) * 0.5) * 7 * shake;
    const dx = Math.round(camX + shakeX);
    const dy = Math.round(camY + shakeY);
    const scale = canvas.width / view.w;

    ctx!.setTransform(1, 0, 0, 1, 0, 0);
    ctx!.imageSmoothingEnabled = true;
    paintSky(dx, scale);

    ctx!.setTransform(scale, 0, 0, scale, view.ox, view.oy);
    const hill = (color: string, parallax: number, amp: number, base: number) => {
      ctx!.fillStyle = color;
      ctx!.beginPath();
      ctx!.moveTo(0, view.h);
      for (let x = 0; x <= view.w; x += 8) {
        const wx = dx * parallax + x;
        const y = base + Math.sin(wx * 0.012) * amp + Math.sin(wx * 0.004 + 2) * amp * 0.6;
        ctx!.lineTo(x, y);
      }
      ctx!.lineTo(view.w, view.h);
      ctx!.closePath();
      ctx!.fill();
    };
    hill("#0c2422", 0.15, 26, view.h * 0.62);
    hill("#102e2a", 0.32, 18, view.h * 0.74);

    ctx!.setTransform(scale, 0, 0, scale, -dx * scale + view.ox, -dy * scale + view.oy);

    for (const s of level.solids) {
      if (s.oneway) {
        if (!drawImageRect(sheets.ledge, s.x, s.y, s.w, s.h, 0.04)) {
          ctx!.fillStyle = "#3d5a45";
          ctx!.fillRect(s.x, s.y, s.w, s.h);
          ctx!.fillStyle = "#2f6b4a";
          ctx!.fillRect(s.x, s.y, s.w, 6);
        }
      } else if (sheets.block) {
        ctx!.save();
        ctx!.beginPath();
        ctx!.rect(s.x, s.y, s.w, s.h);
        ctx!.clip();
        const tw = 48;
        const x0 = Math.floor(s.x / tw) * tw;
        const y0 = Math.floor(s.y / tw) * tw;
        for (let y = y0; y < s.y + s.h; y += tw) {
          for (let x = x0; x < s.x + s.w; x += tw) {
            drawImageRect(sheets.block, x, y, tw + 1, tw + 1, 0.035);
          }
        }
        ctx!.restore();
      } else {
        ctx!.fillStyle = "#1a3330";
        ctx!.fillRect(s.x, s.y, s.w, s.h);
        ctx!.fillStyle = "#2f6b4a";
        ctx!.fillRect(s.x, s.y, s.w, 8);
      }
    }

    for (const m of movers) {
      if (!drawImageRect(sheets.ledge, m.px, m.py, m.w, m.h, 0.05)) {
        ctx!.fillStyle = "#6d5a3a";
        ctx!.fillRect(m.px, m.py, m.w, m.h);
        ctx!.fillStyle = "#2f6b4a";
        ctx!.fillRect(m.px, m.py, m.w, 6);
      }
    }

    for (const sp of level.spikes) {
      if (!drawImageRect(sheets.spike, sp.x, sp.y, sp.w, sp.h, 0)) {
        ctx!.fillStyle = "#8a9096";
        ctx!.beginPath();
        ctx!.moveTo(sp.x, sp.y + sp.h);
        ctx!.lineTo(sp.x + sp.w * 0.5, sp.y);
        ctx!.lineTo(sp.x + sp.w, sp.y + sp.h);
        ctx!.fill();
      }
    }

    level.checkpoints.forEach((c, i) => {
      const lit = i <= cp;
      ctx!.save();
      if (!lit) ctx!.filter = "saturate(0.15) brightness(0.72)";
      if (!drawFeet(sheets.post, c.x, c.y, 78)) {
        ctx!.fillStyle = lit ? "#f0a040" : "#6a6256";
        ctx!.fillRect(c.x - 3, c.y - 58, 6, 58);
        ctx!.beginPath();
        ctx!.arc(c.x, c.y - 64, 8, 0, Math.PI * 2);
        ctx!.fill();
      }
      ctx!.restore();
      if (lit) {
        const g = ctx!.createRadialGradient(c.x, c.y - 62, 2, c.x, c.y - 62, 36);
        g.addColorStop(0, "rgba(240,160,64,0.45)");
        g.addColorStop(1, "rgba(240,160,64,0)");
        ctx!.fillStyle = g;
        ctx!.beginPath();
        ctx!.arc(c.x, c.y - 62, 36, 0, Math.PI * 2);
        ctx!.fill();
      }
    });

    const coinFrame = sheets.coin.length
      ? sheets.coin[Math.floor(time * 8) % sheets.coin.length]!
      : null;
    level.coins.forEach((c, i) => {
      if (got.has(i)) return;
      const bob = Math.sin(time * 3.2 + i) * 3;
      if (!drawFeet(coinFrame, c.x, c.y + 12 + bob, 26)) {
        ctx!.fillStyle = "#f0a040";
        ctx!.beginPath();
        ctx!.arc(c.x, c.y + bob, 8, 0, Math.PI * 2);
        ctx!.fill();
      }
    });

    const flagFrame = sheets.flag.length
      ? sheets.flag[Math.floor(time * 6) % sheets.flag.length]!
      : null;
    if (!drawFeet(flagFrame, level.flag.x, level.flag.y, 92)) {
      ctx!.fillStyle = "#1a1208";
      ctx!.fillRect(level.flag.x - 2, level.flag.y - 78, 4, 78);
      ctx!.fillStyle = "#2f6b4a";
      ctx!.beginPath();
      ctx!.moveTo(level.flag.x, level.flag.y - 76);
      ctx!.lineTo(level.flag.x + 28, level.flag.y - 64);
      ctx!.lineTo(level.flag.x, level.flag.y - 52);
      ctx!.fill();
    }

    const lantern = ctx!.createRadialGradient(
      player.x + PW * 0.7,
      player.y + 10,
      4,
      player.x + PW / 2,
      player.y + 12,
      70,
    );
    lantern.addColorStop(0, "rgba(240,160,64,0.28)");
    lantern.addColorStop(1, "rgba(240,160,64,0)");
    ctx!.fillStyle = lantern;
    ctx!.beginPath();
    ctx!.arc(player.x + PW / 2, player.y + 14, 70, 0, Math.PI * 2);
    ctx!.fill();

    let sprite: Sprite | null = null;
    if (!grounded && sheets.jump.length === 4) {
      const index = jumpAge < 0.07 ? 0 : player.vy < -120 ? 1 : player.vy < 150 ? 2 : 3;
      sprite = sheets.jump[index] ?? null;
    } else if (Math.abs(player.vx) > 28 && grounded && sheets.run.length) {
      sprite = sheets.run[Math.floor(time * 12) % sheets.run.length] ?? null;
    } else if (sheets.idle.length) {
      sprite = sheets.idle[Math.floor(time * 5) % sheets.idle.length] ?? null;
    }

    const sy = grounded ? 1 - 0.2 * squash : 1 + clamp(-player.vy / 1600, -0.1, 0.14);
    const sx = 1 / sy;
    squash = Math.max(0, squash - dt * 5);
    ctx!.save();
    ctx!.translate(player.x + PW / 2, player.y + PH);
    ctx!.scale(player.facing * sx, sy);
    if (sprite) {
      const destH = 62;
      const destW = destH * (sprite.sw / sprite.sh);
      const footFromTop = ((sprite.foot - sprite.sy) / sprite.sh) * destH;
      ctx!.drawImage(
        sprite.img,
        sprite.sx,
        sprite.sy,
        sprite.sw,
        sprite.sh,
        -destW / 2,
        -footFromTop,
        destW,
        destH,
      );
    } else {
      ctx!.fillStyle = "#2f6b4a";
      ctx!.fillRect(-9, -32, 18, 32);
      ctx!.fillStyle = "#f0a040";
      ctx!.fillRect(2, -26, 6, 8);
    }
    ctx!.restore();

    for (const p of particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 280 * dt;
      if (p.life <= 0) continue;
      ctx!.globalAlpha = Math.max(0, p.life / p.max);
      ctx!.fillStyle = p.color;
      ctx!.fillRect(p.x, p.y, p.size, p.size);
    }
    ctx!.globalAlpha = 1;
    for (let i = particles.length - 1; i >= 0; i--) if (particles[i]!.life <= 0) particles.splice(i, 1);

    ctx!.setTransform(1, 0, 0, 1, 0, 0);
    const vig = ctx!.createRadialGradient(
      canvas.width / 2,
      canvas.height / 2,
      canvas.width * 0.3,
      canvas.width / 2,
      canvas.height / 2,
      canvas.width * 0.72,
    );
    vig.addColorStop(0, "rgba(0,0,0,0)");
    vig.addColorStop(1, "rgba(0,0,0,0.38)");
    ctx!.fillStyle = vig;
    ctx!.fillRect(0, 0, canvas.width, canvas.height);

    if (phase === "dead") {
      ctx!.fillStyle = "rgba(12,28,31,0.28)";
      ctx!.fillRect(0, 0, canvas.width, canvas.height);
    }
  }

  function pollPad() {
    padX = 0;
    padJump = false;
    const pads = navigator.getGamepads?.();
    if (!pads) return;
    for (const pad of pads) {
      if (!pad) continue;
      const ax = pad.axes[0] ?? 0;
      if (ax < -0.22 || pad.buttons[14]?.pressed) padX -= 1;
      if (ax > 0.22 || pad.buttons[15]?.pressed) padX += 1;
      if (pad.buttons[0]?.pressed || pad.buttons[1]?.pressed) padJump = true;
    }
    padX = clamp(padX, -1, 1);
  }

  function frame(now: number) {
    pollPad();
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (phase === "play") {
      acc += dt;
      let guard = 0;
      const stepDt = 1 / 120;
      while (acc >= stepDt && guard++ < 8) {
        step(stepDt);
        acc -= stepDt;
        if (phase !== "play") break;
      }
    } else if (phase === "title") {
      time += dt;
      placeMovers(time);
    }
    render(dt);
    raf = requestAnimationFrame(frame);
  }

  function onKeyDown(e: KeyboardEvent) {
    if (!GAME_KEYS.has(e.code)) return;
    e.preventDefault();
    keys.add(e.code);
    if (e.code === "Escape" && !e.repeat) {
      if (phase === "play") phase = "pause";
      else if (phase === "pause") phase = "play";
      emit();
    }
  }
  function onKeyUp(e: KeyboardEvent) {
    keys.delete(e.code);
  }
  function onBlur() {
    keys.clear();
  }

  window.addEventListener("keydown", onKeyDown);
  window.addEventListener("keyup", onKeyUp);
  window.addEventListener("blur", onBlur);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) keys.clear();
  });

  loadLevel(0, "title");
  raf = requestAnimationFrame(frame);

  void (async () => {
    const [idle, run, jump, coin, flag, spike, post, block, ledge] = await Promise.all([
      Promise.all([1, 2, 3, 4].map((n) => loadSprite(`idle-${n}.png`))),
      Promise.all([1, 2, 3, 4].map((n) => loadSprite(`run-${n}.png`))),
      Promise.all([1, 2, 3, 4].map((n) => loadSprite(`jump-${n}.png`))),
      Promise.all([1, 2, 3, 4].map((n) => loadSprite(`coin-${n}.png`))),
      Promise.all([1, 2, 3, 4].map((n) => loadSprite(`flag-${n}.png`))),
      loadSprite("spike.png"),
      loadSprite("checkpoint.png"),
      loadSprite("block.png"),
      loadSprite("ledge.png"),
    ]);
    sheets = {
      idle: idle.filter((s): s is Sprite => !!s),
      run: run.filter((s): s is Sprite => !!s),
      jump: jump.filter((s): s is Sprite => !!s),
      coin: coin.filter((s): s is Sprite => !!s),
      flag: flag.filter((s): s is Sprite => !!s),
      spike,
      post,
      block,
      ledge,
    };
  })();

  const probe = {
    getX: () => player.x,
    getY: () => player.y,
    getSpeed: () => Math.abs(player.vx),
    getYaw: () => player.facing,
    getPhase: () => phase,
    getTime: () => time,
    getMovers: () => movers.map((m) => ({ x: m.px, y: m.py, w: m.w, h: m.h })),
    setSteer: (v: number) => {
      steer = v;
    },
    setKeys: (codes: string[]) => {
      injected.clear();
      for (const code of codes) injected.add(code);
    },
  };
  window.__controlsTest = probe;

  return {
    start(index: number) {
      sfx.unlock();
      loadLevel(index, "play");
    },
    respawn() {
      sfx.unlock();
      got = new Set(snap.coins);
      cp = snap.cp;
      placePlayer(snap.x, snap.y);
      phase = "play";
      emit();
    },
    retry() {
      sfx.unlock();
      loadLevel(levelIndex, "play");
    },
    pause() {
      if (phase === "play") {
        phase = "pause";
        emit();
      }
    },
    resume() {
      if (phase === "pause") {
        phase = "play";
        prevJump = held("Space") || held("KeyW") || held("ArrowUp") || touch.jump;
        emit();
      }
    },
    title() {
      phase = "title";
      loadLevel(0, "title");
    },
    setTouch(key, down) {
      if (key === "drop") {
        if (down) touch.drop = true;
        return;
      }
      touch[key] = down;
    },
    unlock() {
      sfx.unlock();
    },
    destroy() {
      cancelAnimationFrame(raf);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
      if (window.__controlsTest === probe) delete window.__controlsTest;
    },
  };
}

declare global {
  interface Window {
    __controlsTest?: {
      getYaw: () => number;
      getSpeed: () => number;
      getX?: () => number;
      getY?: () => number;
      getPhase?: () => string;
      getTime?: () => number;
      getMovers?: () => { x: number; y: number; w: number; h: number }[];
      setSteer?: (v: number) => void;
      setKeys?: (codes: string[]) => void;
    };
  }
}

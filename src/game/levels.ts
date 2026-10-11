export type Rect = { x: number; y: number; w: number; h: number };

export type Solid = Rect & { oneway?: boolean };

export type MoverDef = {
  x: number;
  y: number;
  w: number;
  h: number;
  axis: "x" | "y";
  distance: number;
  period: number;
  phase: number;
};

export type Level = {
  name: string;
  blurb: string;
  width: number;
  height: number;
  killY: number;
  spawn: { x: number; y: number };
  solids: Solid[];
  movers: MoverDef[];
  coins: { x: number; y: number }[];
  spikes: Rect[];
  checkpoints: { x: number; y: number }[];
  flag: { x: number; y: number };
};

const spike = (x: number, ground: number): Rect => ({ x, y: ground - 34, w: 40, h: 34 });

export const LEVELS: Level[] = [
  {
    name: "Wick Road",
    blurb: "Run, jump, and ride the stone across the gap.",
    width: 3120,
    height: 760,
    killY: 740,
    spawn: { x: 88, y: 512 },
    solids: [
      { x: 0, y: 512, w: 704, h: 240 },
      { x: 960, y: 512, w: 560, h: 240 },
      { x: 1600, y: 448, w: 190, h: 26, oneway: true },
      { x: 1880, y: 384, w: 190, h: 26, oneway: true },
      { x: 2160, y: 512, w: 960, h: 240 },
    ],
    movers: [
      { x: 740, y: 512, w: 170, h: 22, axis: "x", distance: 120, period: 3.3, phase: 0 },
    ],
    coins: [
      { x: 180, y: 460 },
      { x: 300, y: 460 },
      { x: 430, y: 440 },
      { x: 560, y: 460 },
      { x: 820, y: 420 },
      { x: 910, y: 400 },
      { x: 1360, y: 450 },
      { x: 1688, y: 400 },
      { x: 1968, y: 332 },
      { x: 2400, y: 456 },
      { x: 2620, y: 440 },
      { x: 2840, y: 456 },
    ],
    spikes: [spike(1180, 512), spike(1340, 512)],
    checkpoints: [{ x: 1040, y: 512 }],
    flag: { x: 2980, y: 512 },
  },
  {
    name: "Ash Span",
    blurb: "The second jump is what clears the broken stair.",
    width: 2680,
    height: 1020,
    killY: 1000,
    spawn: { x: 80, y: 704 },
    solids: [
      { x: 0, y: 704, w: 420, h: 280 },
      { x: 500, y: 608, w: 176, h: 26, oneway: true },
      { x: 760, y: 480, w: 176, h: 26, oneway: true },
      { x: 980, y: 820, w: 640, h: 180 },
      { x: 1560, y: 480, w: 240, h: 26, oneway: true },
      { x: 1880, y: 300, w: 680, h: 28, oneway: true },
    ],
    movers: [
      { x: 980, y: 480, w: 170, h: 22, axis: "x", distance: 120, period: 3.4, phase: 0 },
      { x: 1320, y: 480, w: 170, h: 22, axis: "x", distance: 140, period: 3.4, phase: Math.PI },
      { x: 1700, y: 390, w: 220, h: 22, axis: "y", distance: 90, period: 4.2, phase: 0 },
    ],
    coins: [
      { x: 160, y: 648 },
      { x: 280, y: 640 },
      { x: 580, y: 556 },
      { x: 840, y: 420 },
      { x: 1120, y: 400 },
      { x: 1320, y: 390 },
      { x: 1660, y: 420 },
      { x: 1860, y: 250 },
      { x: 2140, y: 246 },
      { x: 2360, y: 246 },
    ],
    spikes: [
      spike(1080, 820),
      spike(1180, 820),
      spike(1280, 820),
      spike(1380, 820),
      spike(1480, 820),
    ],
    checkpoints: [
      { x: 840, y: 480 },
      { x: 1660, y: 480 },
    ],
    flag: { x: 2400, y: 300 },
  },
  {
    name: "Moss Crown",
    blurb: "Two lifts, a pit of iron, then the last gate.",
    width: 3920,
    height: 1120,
    killY: 1080,
    spawn: { x: 84, y: 768 },
    solids: [
      { x: 0, y: 768, w: 760, h: 280 },
      { x: 900, y: 768, w: 280, h: 280 },
      { x: 1120, y: 960, w: 760, h: 140 },
      { x: 1880, y: 768, w: 360, h: 280 },
      { x: 2320, y: 672, w: 168, h: 26, oneway: true },
      { x: 2560, y: 544, w: 168, h: 26, oneway: true },
      { x: 2800, y: 416, w: 180, h: 26, oneway: true },
      { x: 3040, y: 232, w: 640, h: 28, oneway: true },
    ],
    movers: [
      { x: 1240, y: 768, w: 180, h: 22, axis: "x", distance: 160, period: 3.2, phase: 0 },
      { x: 1630, y: 768, w: 180, h: 22, axis: "x", distance: 150, period: 3.2, phase: Math.PI },
      { x: 2920, y: 324, w: 200, h: 22, axis: "y", distance: 92, period: 3.8, phase: 0.4 },
    ],
    coins: [
      { x: 200, y: 710 },
      { x: 340, y: 700 },
      { x: 480, y: 690 },
      { x: 700, y: 710 },
      { x: 1020, y: 710 },
      { x: 1260, y: 680 },
      { x: 1560, y: 660 },
      { x: 1980, y: 710 },
      { x: 2400, y: 620 },
      { x: 2640, y: 490 },
      { x: 2888, y: 360 },
      { x: 3040, y: 180 },
      { x: 3280, y: 176 },
      { x: 3480, y: 176 },
    ],
    spikes: [
      spike(420, 768),
      spike(640, 768),
      spike(1220, 960),
      spike(1320, 960),
      spike(1440, 960),
      spike(1560, 960),
      spike(1680, 960),
    ],
    checkpoints: [
      { x: 1000, y: 768 },
      { x: 2040, y: 768 },
    ],
    flag: { x: 3520, y: 232 },
  },
];

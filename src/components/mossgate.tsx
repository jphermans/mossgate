import { useEffect, useRef, useState, type PointerEvent } from "react";
import { ChevronDown, ChevronLeft, ChevronRight, Coins, Pause, Play, RotateCcw } from "lucide-react";
import { LEVELS } from "@/game/levels";
import { createGame, type GameApi, type Hud } from "@/game/engine";

const initial: Hud = {
  phase: "title",
  level: 0,
  name: LEVELS[0]!.name,
  coins: 0,
  total: LEVELS[0]!.coins.length,
  checkpoint: false,
  jumps: 2,
  hint: "",
  cleared: [false, false, false],
  best: [0, 0, 0],
};

export function Mossgate() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gameRef = useRef<GameApi | null>(null);
  const [hud, setHud] = useState<Hud>(initial);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const game = createGame(canvas, setHud);
    gameRef.current = game;
    return () => {
      game.destroy();
      gameRef.current = null;
    };
  }, []);

  const game = () => gameRef.current;

  const hold = (key: "left" | "right" | "jump" | "down") => ({
    onPointerDown: (event: PointerEvent<HTMLButtonElement>) => {
      event.preventDefault();
      event.currentTarget.setPointerCapture(event.pointerId);
      event.currentTarget.dataset.pressed = "true";
      game()?.setTouch(key, true);
      game()?.unlock();
    },
    onPointerUp: (event: PointerEvent<HTMLButtonElement>) => {
      event.currentTarget.dataset.pressed = "false";
      game()?.setTouch(key, false);
    },
    onPointerCancel: (event: PointerEvent<HTMLButtonElement>) => {
      event.currentTarget.dataset.pressed = "false";
      game()?.setTouch(key, false);
    },
    onLostPointerCapture: (event: PointerEvent<HTMLButtonElement>) => {
      event.currentTarget.dataset.pressed = "false";
      game()?.setTouch(key, false);
    },
    onContextMenu: (event: PointerEvent<HTMLButtonElement>) => event.preventDefault(),
  });

  const drop = {
    onPointerDown: (event: PointerEvent<HTMLButtonElement>) => {
      event.preventDefault();
      event.currentTarget.dataset.pressed = "true";
      game()?.setTouch("drop", true);
      game()?.unlock();
    },
    onPointerUp: (event: PointerEvent<HTMLButtonElement>) => {
      event.currentTarget.dataset.pressed = "false";
    },
    onPointerCancel: (event: PointerEvent<HTMLButtonElement>) => {
      event.currentTarget.dataset.pressed = "false";
    },
    onContextMenu: (event: PointerEvent<HTMLButtonElement>) => event.preventDefault(),
  };

  return (
    <div className="shell relative flex h-dvh flex-col bg-bg text-fg" data-phase={hud.phase}>
      <div className="stage relative min-h-0 flex-1">
        <canvas ref={canvasRef} className="absolute inset-0 h-full w-full touch-none" aria-hidden />
        {hud.phase === "play" ? (
          <div className="hud pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between gap-2">
            <div className="pointer-events-auto flex items-center gap-2 rounded-full border border-border bg-bg/80 px-3 py-2 backdrop-blur-md">
              <Coins className="size-4 text-primary" aria-hidden />
              <span className="font-sans text-sm font-semibold tabular-nums">
                {hud.coins}
                <span className="text-muted">/{hud.total}</span>
              </span>
              <span className="flex gap-1" aria-label={hud.jumps === 1 ? "1 jump left" : `${hud.jumps} jumps left`}>
                {[0, 1].map((i) => (
                  <span
                    key={i}
                    className={"h-1.5 w-4 rounded-full " + (hud.jumps > i ? "bg-primary" : "bg-border")}
                  />
                ))}
              </span>
            </div>
            <div className="pointer-events-none min-w-0 flex-1 pt-2 text-center">
              <p className="truncate font-display text-lg leading-none">{hud.name}</p>
              <p className={"mt-1 truncate font-sans text-xs " + (hud.hint ? "font-semibold text-primary" : "text-muted")}>
                {hud.hint || (hud.checkpoint ? "Lantern set" : "No lantern yet")}
              </p>
            </div>
            <button
              type="button"
              className="pointer-events-auto flex size-11 shrink-0 items-center justify-center rounded-full border border-border bg-bg/80 text-fg backdrop-blur-md"
              onClick={() => game()?.pause()}
              aria-label="Pause"
            >
              <Pause className="size-4" />
            </button>
          </div>
        ) : null}

        {hud.phase !== "play" ? (
          <div className="menu-scroll absolute inset-0 overflow-y-auto">
            <div className="flex min-h-full items-center justify-center">
            <div className="panel w-full max-w-md rounded-2xl border border-border bg-bg/85 p-5 backdrop-blur-md sm:p-6">
              {hud.phase === "title" ? (
                <>
                  <p className="font-sans text-xs font-semibold tracking-widest text-primary uppercase">
                    Dusk ruins
                  </p>
                  <h1 className="mt-1 font-display text-4xl leading-none text-fg sm:text-5xl">Mossgate</h1>
                  <p className="mt-3 max-w-sm font-sans text-base leading-relaxed text-muted">
                    Keep the lantern lit. Run, jump, and jump again before the dark takes the wick.
                  </p>
                  <button
                    type="button"
                    className="mt-5 flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-primary px-5 font-sans text-base font-semibold text-primary-fg"
                    onClick={() => game()?.start(0)}
                  >
                    <Play className="size-4" aria-hidden />
                    Start
                  </button>
                  <ul className="mt-4 flex flex-col gap-2">
                    {LEVELS.map((level, index) => (
                      <li key={level.name}>
                        <button
                          type="button"
                          className="flex min-h-12 w-full items-center justify-between gap-3 rounded-xl border border-border bg-surface px-3 py-2 text-left"
                          onClick={() => game()?.start(index)}
                        >
                          <span>
                            <span className="block font-sans text-sm font-semibold text-fg">
                              {level.name}
                              {hud.cleared[index] ? (
                                <span className="ml-2 font-medium text-primary">Clear</span>
                              ) : null}
                            </span>
                            <span className="block font-sans text-xs text-muted">{level.blurb}</span>
                          </span>
                          <span className="shrink-0 font-sans text-xs text-muted tabular-nums">
                            {hud.best[index] ? `Best ${hud.best[index]}` : `${level.coins.length} coins`}
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                  <p className="mt-4 font-sans text-xs leading-relaxed text-muted">
                    On a phone, the buttons sit under the road. Jump again while you are in the air.
                    Drop falls through a thin ledge. A keyboard uses A and D or the arrows, and Space,
                    W, or Up.
                  </p>
                </>
              ) : null}

              {hud.phase === "pause" ? (
                <>
                  <h2 className="font-display text-4xl leading-none">Paused</h2>
                  <p className="mt-2 font-sans text-sm text-muted">{hud.name}</p>
                  <div className="mt-5 flex flex-col gap-2">
                    <button
                      type="button"
                      className="min-h-12 rounded-full bg-primary px-5 font-sans font-semibold text-primary-fg"
                      onClick={() => game()?.resume()}
                    >
                      Resume
                    </button>
                    <button
                      type="button"
                      className="min-h-12 rounded-full border border-border bg-surface px-5 font-sans font-semibold"
                      onClick={() => game()?.retry()}
                    >
                      Restart level
                    </button>
                    <button
                      type="button"
                      className="min-h-12 rounded-full border border-border px-5 font-sans font-semibold text-muted"
                      onClick={() => game()?.title()}
                    >
                      All gates
                    </button>
                  </div>
                </>
              ) : null}

              {hud.phase === "dead" ? (
                <>
                  <h2 className="font-display text-4xl leading-none">The wick went out</h2>
                  <p className="mt-3 font-sans text-sm leading-relaxed text-muted">
                    {hud.checkpoint
                      ? "The last lantern still remembers you."
                      : "Back to the start of the road."}{" "}
                    Coins after that lantern return to the moss.
                  </p>
                  <div className="mt-5 flex flex-col gap-2">
                    <button
                      type="button"
                      className="min-h-12 rounded-full bg-primary px-5 font-sans font-semibold text-primary-fg"
                      onClick={() => game()?.respawn()}
                    >
                      Relight
                    </button>
                    <button
                      type="button"
                      className="flex min-h-12 items-center justify-center gap-2 rounded-full border border-border bg-surface px-5 font-sans font-semibold"
                      onClick={() => game()?.retry()}
                    >
                      <RotateCcw className="size-4" aria-hidden />
                      Restart level
                    </button>
                    <button
                      type="button"
                      className="min-h-12 rounded-full border border-border px-5 font-sans font-semibold text-muted"
                      onClick={() => game()?.title()}
                    >
                      All gates
                    </button>
                  </div>
                </>
              ) : null}

              {hud.phase === "win" ? (
                <>
                  <p className="font-sans text-xs font-semibold tracking-widest text-primary uppercase">
                    Gate open
                  </p>
                  <h2 className="mt-1 font-display text-4xl leading-none">
                    {hud.level === LEVELS.length - 1 ? "Mossgate yields" : hud.name}
                  </h2>
                  <p className="mt-3 font-sans text-sm text-muted">
                    {hud.coins} of {hud.total} coins gathered.
                  </p>
                  <div className="mt-5 flex flex-col gap-2">
                    {hud.level < LEVELS.length - 1 ? (
                      <button
                        type="button"
                        className="min-h-12 rounded-full bg-primary px-5 font-sans font-semibold text-primary-fg"
                        onClick={() => game()?.start(hud.level + 1)}
                      >
                        Next gate
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="min-h-12 rounded-full bg-primary px-5 font-sans font-semibold text-primary-fg"
                        onClick={() => game()?.title()}
                      >
                        All gates
                      </button>
                    )}
                    <button
                      type="button"
                      className="min-h-12 rounded-full border border-border bg-surface px-5 font-sans font-semibold"
                      onClick={() => game()?.retry()}
                    >
                      Replay
                    </button>
                    {hud.level < LEVELS.length - 1 ? (
                      <button
                        type="button"
                        className="min-h-12 rounded-full border border-border px-5 font-sans font-semibold text-muted"
                        onClick={() => game()?.title()}
                      >
                        All gates
                      </button>
                    ) : null}
                  </div>
                </>
              ) : null}
            </div>
            </div>
          </div>
        ) : null}
      </div>

      <div className="controls">
        <div className="flex items-end gap-2">
          <button type="button" className="pad" aria-label="Run left" {...hold("left")}>
            <ChevronLeft className="size-7" />
          </button>
          <button type="button" className="pad" aria-label="Run right" {...hold("right")}>
            <ChevronRight className="size-7" />
          </button>
        </div>
        <div className="flex items-end gap-2">
          <button type="button" className="pad pad-drop" aria-label="Drop through a ledge" {...drop}>
            <ChevronDown className="size-6" />
          </button>
          <button type="button" className="pad pad-jump" aria-label="Jump" {...hold("jump")}>
            Jump
          </button>
        </div>
      </div>
    </div>
  );
}

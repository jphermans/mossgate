# Mossgate — Dusk Ruins

A 2D dusk-ruins platformer for iPhone. Native SwiftUI + SpriteKit + GameKit, built by
[JPHsystems](https://github.com/jphermans).

**0.6.0 (build 16)** · 36 gates · 6 worlds (1 free, 5 paid) · iOS 18.0+ · portrait splash,
landscape gameplay

Public support, privacy and changelog page: <https://jphermans.github.io/mossgate-support/>

---

## The game

You carry a lantern along a ruined causeway toward a gate. Falling, or touching a bramble,
costs a unit of light. Three units a run; collect a lantern to win one back. Lose all three
and the run is over.

- **Six worlds, 36 gates.** Mossgate Dusk is free; the other five are the single
  in-app purchase, and each world only opens once the one before it is finished.
- **6 gates per world, and most of them are rebuilt every run.** Each world opens
  with its authored gates — they are the ones that teach — and the rest are
  generated, so the back half of the game is new each time you play.
- **Every gate is left-to-right**, so the controls stay two thumbs: move, jump, down.
- **Coins are the score.** Twelve or so per gate; your best count per gate is kept.

## Repo layout

```
ios/                     the shipping app (this is the part that matters)
  Mossgate/              SwiftUI screens, the SpriteKit scene, audio, gamepad
  Mossgate/Resources/
    Sprites/             PNG sprite art, addressed by base name ("idle-1", "coin-1", ...)
    Music/               dusk.m4a, ember.m4a
  project.yml            xcodegen source of truth — new files are picked up from the dir,
                         but you must re-run `xcodegen generate` after adding one
scripts/                 version bumping, music generation, promo video renderer
src/, server/, public/   the original browser build this was ported from (reference only)
```

The `src/game/engine.ts` in the web tree is still the reference for physics semantics — the
Swift port deliberately matches its constants and step order.

## Building

`project.yml` is the source of truth. It globs the `Mossgate` directory, so a new `.swift`
file is included automatically — but only after the project is regenerated:

```sh
cd ios
xcodegen generate
xcodebuild -project Mossgate.xcodeproj -scheme Mossgate \
  -sdk iphonesimulator -configuration Debug \
  -destination 'id=<SIMULATOR_UDID>' CODE_SIGNING_ALLOWED=NO build
```

Simulators run headless, so drive them with `simctl` rather than the Simulator app:

```sh
xcrun simctl install <UDID> <path-to>/Mossgate.app
xcrun simctl launch --console-pty <UDID> io.jphsystems.mossgate -SkipSplash 1 -StartInLevel 0
```

`--console-pty` captures `print`, but the stream is buffered — a run that only prints during
scene setup can come back empty. Passing `-StartInLevel` makes the scene log as well, which
flushes it.

## Versioning

`CURRENT_PROJECT_VERSION` bumps on **every** code change batch, `MARKETING_VERSION` at
milestones. `ios/project.yml` holds both; never edit them by hand.

```sh
./scripts/bump-ios-version.py --patch        # 0.5.0 (14) -> 0.5.1 (15)
./scripts/bump-ios-version.py --minor        # 0.5.0 (14) -> 0.6.0 (15)
./scripts/bump-ios-version.py --set 1.0 --no-xcodegen
```

## Four systems worth knowing about

### 0. The gates are generated, and the paywall is real

`ios/Mossgate/LevelGen.swift` builds a gate by grammar: walk right, and at each
step pick a feature (flat run, gap, step up, step down, bramble run, one-way
bridge, mover crossing) inside a limit the physics can actually clear — a gap no
wider than a running jump, a step no higher than one. That is a **static**
guarantee rather than a "can the bot finish it" check, on purpose: gating
generation on the bot would delete every feature it cannot handle and collapse the
output to flat ground. `LevelGen.inspect` measures what a gate actually asks for;
`-TestLevelGen 1` prints the table.

Two rules decide whether a world can be played, in this order: is it the free one,
then is the full game owned **and** every world before it finished. They live in
`SettingsStore.worldUnlocked` so the paywall has one definition. `Store.swift`
writes `hasFullGame` from StoreKit's own entitlement records — not from what the
purchase call returned, because entitlements are what survive a reinstall.

### 1. The worlds reshuffle every run

Each launch draws a random run seed (`SettingsStore.runSeed`, deliberately not persisted).
Four things derive from it: the sky palette (hue-rotated ±40°, saturation and brightness
scaled), the starfield, the pickup positions, and the mover timing. `Setup → New worlds`
shows the seed and can reshuffle live.

The one thing that never changes is the platform geometry — those layouts are hand-designed
and provably reachable, and a reshuffle must not be able to hand you an impossible jump.

### 2. Coins are placed by an autonomous runner

`ios/Mossgate/Autopilot.swift` holds `Sim`, a headless replica of the player physics with no
nodes, no audio and no display, so a whole level plays in milliseconds. Two things sit on it:

- **`run(level:phase:period:)`** — a runner that plays start-to-gate and returns its path.
  Coins are sampled along that path by **arc length**, not by index: the path is recorded once
  per 1/120 s substep, so indexing would bunch coins at the top of every jump.
- **`reachable(from:...)` / `variedCoin(near:...)`** — a ballistic reachability probe, used
  when the runner cannot finish. It stands the player on the surface under a coin's authored
  position, fires the sensible launches, and collects every position the player's centre
  passed through. The coin goes somewhere on that arc.

Both give the same guarantee, which is the entire point: **a coin sits where a simulated
player physically was**, so no reshuffle can strand one behind a jump that cannot be made.

Measured state of the runner, from `-TestAutopilot 1`:

| level | result |
| --- | --- |
| 0 Wick Road | reached the gate (11.8 s, 1418 route points, 3 ms to compute) |
| 1–4 | walks into a bramble around t≈5–7 s |
| 5–6 | falls past the kill plane around t≈3–5 s |

**1 of 7 solved.** So Wick Road samples coins from the route and every other level uses the
probe. The policy is the weak part, not the simulation: it only looks for brambles near its
feet, so it walks into ones it is about to land on. Improving it raises that number, and every
level it starts solving converts from probe to route automatically.

### 3. Test hooks

Launch arguments, all read on startup. They exist because the simulator is headless and a tap
cannot be scripted.

| flag | what it does |
| --- | --- |
| `-SkipSplash 1` | skip the splash screen |
| `-StartInLevel <n>` | jump straight into gate `n` |
| `-Seed <n>` | force the run seed, for comparing two worlds |
| `-OpenSetup 1` / `-OpenHelp 1` | present that sheet on the title screen |
| `-SetupLarge 1` | open Setup at its tall detent (the controller section is below the fold) |
| `-TestAutopilot 1` | play every gate with the runner and print the table above |
| `-TestSeed 1` | report what the run seed changed this load |
| `-TestMovers 1` | prove no moving platform ever overlaps the land |
| `-TestDeath 1` | walk the light counter 3/3 → 0/3 and check game-over + start-over |
| `-TestDown 1` | measure what the DOWN pad actually changes |
| `-TestDrop 1` | measure the drop-through on a one-way ledge |
| `-TestGamepad 1` | assert the controller mappings |
| `-TestSfx 1` | fire the sound effects |
| `-PlaceAt x,y` | teleport the player, for photographing a part of a level |

Rules for these: they must **measure**, not assert — print the before and after. They must be
read from `ProcessInfo` at the point of use, so no state leaks between runs. And they must
never change gameplay when the flag is absent.

## Assets

- **Sprites** are loose PNGs in `Resources/Sprites/`, loaded by base name. The lantern is the
  exception: it is drawn at runtime in `GameArt.swift`, shared with the in-app help screen so
  the two can never drift apart.
- **Music** is generated by `scripts/make-music.py` (AAC, seamless loops by construction —
  any note crossing the buffer end wraps onto the head). Phone speakers cannot reproduce
  sub-60 Hz energy, where it just buzzes, so the generator band-limits and high-passes.
- **Sound effects** are synthesised in `AudioEngine.swift`, band-limited the same way.

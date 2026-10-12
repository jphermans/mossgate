# Mossgate — Dusk Ruins

A 2D dusk-ruins platformer for iPhone. Native SwiftUI + SpriteKit + GameKit, built by
[JPHsystems](https://github.com/jphermans).

**0.7.44 (build 67)** · 36 gates · 6 worlds (1 free, 5 paid) · iOS 18.0+ · iPhone · portrait
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
- **The Daily Gate**, free and above the worlds on the title screen: one gate, one seed per
  calendar day, the same for every player — and a different one tomorrow. Coins are the score
  and the streak counts the days you finish it (`DailyGate.swift`).

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

### 2. Coins are placed for a jump, and cannot be out of reach

`ios/Mossgate/Autopilot.swift` holds `Sim`, a headless replica of the player physics with no
nodes, no audio and no display, so a whole level plays in milliseconds. Coin placement runs on
it in three steps, in order of preference:

1. **A random spot an ordinary jump can take.** A random x along the gate, hung 45–95 above
   the topmost surface there — above the player's 32-unit height, so walking past never takes
   it. Measured from the *topmost* surface because that is the one the proof stands on;
   measuring from the floor instead let a coin hang over a pit the proof never used.
2. **The level's own position**, if that one passes the proof.
3. **A guaranteed grab.** 14 above the nearest surface, which is inside the player's standing
   pickup radius. Arithmetic, not a simulation, so it cannot fail.

Steps 1 and 2 are proofs and can run out of budget; step 3 is why the invariant holds whatever
happens. `-TestCoins 1` asserts it: `notCollectible 0` and `unplaced 0` across all 36 gates,
with `belowHeadHeight 0` everywhere — no coin in the game can be taken by walking through it.

The proof is deliberately a **single** jump (`singleJumpOnly`). An earlier version accepted a
precisely timed double jump, which is technically reachable and in practice reads as jumping at
a coin and nothing happening.

**Two bounds, both load-bearing.** A layout is computed on the main thread inside a level load,
so it has a 250 ms deadline and a proof budget. The first version had neither and tried up to 60
candidate spots per coin with a full proof each — roughly 400,000 simulation steps for one coin
— and iOS terminated the app with `Thread 1: signal SIGTERM`. Cost is printed per gate and now
runs 0–7 ms.

Layouts are keyed on level, run seed **and an attempt counter**, bumped on a retry and on
arriving at a different gate. A layout pass re-entering `startLevel` deliberately does *not*
bump it: that is what keeps the coins still while the view resizes, without making them
identical on a second attempt. If a gate is going too easily — 20 s in, no death this attempt,
60% of the coins taken — the coins you have not collected move to new spots once, with a small
warm burst so the change is noticed.

### 2b. The runner, still here as an attract mode

The same simulation carries `run(level:phase:period:)`, an autonomous player that plays
start-to-gate and returns its path. It no longer places coins, but the policy is the seed of an
attract mode. Measured from `-TestAutopilot 1`:

| level | result |
| --- | --- |
| 0 Wick Road | reached the gate (11.8 s, 1418 route points, 3 ms to compute) |
| 1–4 | walks into a bramble around t≈5–7 s |
| 5–6 | falls past the kill plane around t≈3–5 s |

**1 of 7 solved.** The policy is the weak part, not the simulation: it only looks for brambles
near its feet, so it walks into ones it is about to land on.

### 3. Test hooks

Launch arguments, all read on startup. They exist because the simulator is headless and a tap
cannot be scripted.

| flag | what it does |
| --- | --- |
| `-SkipSplash 1` | skip the splash screen |
| `-ForceClosed 1` / `-ForceOpen 1` | Pretend an iPhone Duo is shut or open, so the outer-display portrait layout and the refusal to start a run can be exercised on any simulator. |
| `-ShowNotice 1` | Raise the app's own alert at launch, so the styled panel can be inspected without a tap. |
| `-TapBegin 1` | Do what "Tap to begin" does. The simulator cannot tap, so this is the only way to exercise the splash gate; it calls the same function the button does. |
| `-ForceCloseAfter <s>` | Open, then fold the Duo `s` seconds in — the only way to exercise closing returning to the splash, since the simulator cannot fold. |
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
| `-TestCoins 1` | every placed coin against the game's own pickup rule, with one ordinary jump |
| `-TestLevelGen 1` | generate every gate for this seed and report clearance and pits |
| `-TestProgress 1` | save progress, tear the gate down, reload it, report the round trip |
| `-TestEdge 1` | the foothold rule either side of its boundary |
| `-TestSettings 1` | report the stored preferences; `-TestSettings set` changes them and resets progress first |
| `-CollapseWorlds 1` | collapse every world card on the title screen, for screenshots |
| `-UnlockFullGame 1` | pretend the Full Game is owned, for screenshots |
| `-DemoPlay 1` | filming harness: drives the player (right + hops) and recovers from death. Gives up after 40s, and any real press on a control cancels it |
| `-OpenResetConfirm 1` | open straight into the reset card |
| `-CompleteWorld <n>` | mark world `n` cleared, in memory only |
| `-WinNow 1` | clear the current gate for real (persists) |
| `-TestCoinSprites 1` | every coin is drawn where it can be taken, then takes one and checks it leaves the screen |

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

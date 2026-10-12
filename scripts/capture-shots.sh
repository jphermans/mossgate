#!/usr/bin/env bash
#
# Capture the App Store screenshot packs, straight from the running game.
#
# One command, because the alternative is a manual ritual that quietly rots: the packs
# get captured once, the game changes, and nobody notices the shots are of a build that
# no longer exists.
#
# WHAT IT PRODUCES
#   AppStore/Screenshots/iphone-6.7/   2796x1290 landscape  (iPhone 6.7")
#
# iPhone ONLY, by decision: the app targets the iPhone device family, so it does not support
# iPad and the App Store does not ask for an iPad set. An earlier version of this rig built a
# 13" iPad pack as well, which was wasted work the moment the device family said "1". If the
# family ever goes back to "1,2", the iPad half has to come back — dropping it is only
# correct while the binary claims iPhone only.
#
# WHY LANDSCAPE
#   The game is landscape-only during play, so the landscape sizes are the honest ones.
#   Both are accepted by App Store Connect; a portrait pack for a landscape game looks
#   wrong in the carousel.
#
# WHY THE FORCED RESIZE
#   A simulator capture is the device's native framebuffer, which is not one of the
#   accepted sizes: 2622x1206 from a 16 Pro, and the iPad 13" is 2752x2064. `sips -z`
#   forces the exact size, and the aspect deltas here are 0.3% and 0.7% — below what an
#   eye can see. Apple validates dimensions exactly and rejects anything else, so this
#   is the step that decides whether the upload works at all.
#
# WHY THESE SIX SCREENS AND NOT THE SPLASH
#   Guideline 2.3.3 wants the app IN USE. The splash, the setup screen and anything
#   showing a build number are excluded deliberately, not by omission — the pack is
#   built from a list so a frame cannot be dragged in by accident.
#
# Usage:  ./scripts/capture-shots.sh [--keep-frames]

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$ROOT/AppStore/Screenshots"
TMP="${TMPDIR:-/tmp}/mossgate-shots"
BUNDLE="io.jphsystems.mossgate"

IPHONE_UDID="175BC23E-E750-4F8B-BC55-77EFDCB793E1"
# Landscape, WIDTH x HEIGHT, spelled the way App Store Connect names them.
#
# `sips -z` takes HEIGHT then WIDTH. The first version of this file handed it these
# constants in this order, so every screenshot came out portrait and squashed — the
# verify pass at the bottom caught it, which is the only reason it was not discovered
# at upload time.
#
# iPhone is the 6.7" set: a 16 Pro captures 1206x2622 (a 6.3" class, optional only if a
# larger set exists), and forcing it to 1290x2796 is a 0.4% aspect change, which is below
# what an eye can see.
#
# iPad is gone: the app targets the iPhone device family, so it does not run on iPad and
# Apple does not require an iPad set. See the note at the top if that ever changes.
# iPhone is the 6.9" class: Apple's required slot for 2026 submissions, native 1320x2868
# portrait, so 2868x1320 landscape. The 6.7" set is built alongside it because older guidance
# named 2796x1290 as the requirement and sources still disagree about which is accepted alone;
# both come from the same captures, so there is no reason to guess. A 16 Pro captures
# 1206x2622 (a 6.3" class, optional when a larger set exists), and forcing it up is a ~0.3%
# aspect change, below what an eye can see.
IPHONE_SHOT="2868x1320"
IPHONE_SHOT_67="2796x1290"

mkdir -p "$TMP"

# An interpreter that can actually import PIL.
#
# Not bare `python3`: a background run resolved a different interpreter than an interactive
# shell and had no PIL, so the flatten step silently failed while the resize step worked.
# Ask each candidate rather than trusting PATH.
PY=""
for cand in /usr/bin/python3 python3 /opt/homebrew/bin/python3; do
  if "$cand" -c 'import PIL' >/dev/null 2>&1; then PY="$cand"; break; fi
done
[ -n "$PY" ] || say "note: no python with PIL — screenshots will be re-encoded as JPEG"

say() { printf '%s\n' "$*"; }

app_path() {
  local p
  p=$(xcodebuild -project "$ROOT/ios/Mossgate.xcodeproj" -scheme Mossgate \
        -sdk iphonesimulator -configuration Debug -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
  printf '%s/Mossgate.app' "$p"
}

ensure_device() {
  # Echoes a UDID. Creates the 13" iPad on demand: it is 4:3, which is the aspect the
  # iPad pack wants. An 11" iPad is 1.44:1 and forcing it into 2732x2048 would squash
  # the image by 7%, which IS visible.
  local name="$1" type="$2" rt
  rt=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | head -1)
  local found
  found=$(xcrun simctl list devices available | grep -F "$name (" | head -1 | grep -oE '[0-9A-F-]{36}')
  if [ -n "$found" ]; then printf '%s' "$found"; return; fi
  xcrun simctl create "$name" "$type" "$rt" 2>/dev/null
}

boot() {
  xcrun simctl boot "$1" >/dev/null 2>&1
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
}

# capture <device> <pack> <name> <launch args...>
capture() {
  local dev="$1" pack="$2" name="$3"; shift 3
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1
  # shellcheck disable=SC2086
  xcrun simctl launch "$dev" "$BUNDLE" -SkipSplash 1 $* >/dev/null 2>&1
  sleep 6
  xcrun simctl io "$dev" screenshot "$TMP/$name.png" >/dev/null 2>&1
  [ -s "$TMP/$name.png" ] || { say "  FAILED: $name"; return 1; }
  say "  $name"
}

# pack <device> <dir> <size>
pack() {
  local dev="$1" dir="$2" size="$3"
  rm -rf "$dir"; mkdir -p "$dir"
  say "=== $dir ==="
  ensure_booted "$dev"

  capture "$dev" "$dir" "01-first-gate"     -StartInLevel 0
  capture "$dev" "$dir" "02-the-climb"      -StartInLevel 2
  capture "$dev" "$dir" "03-later-world"    -UnlockFullGame 1 -StartInLevel 24
  capture "$dev" "$dir" "04-last-world"     -UnlockFullGame 1 -StartInLevel 30
  capture "$dev" "$dir" "05-how-to-play"    -OpenHelp 1
  capture "$dev" "$dir" "06-daily-gate"     -UnlockFullGame 1 -StartInLevel 5 -Seed 20261012

  # Resize to the exact accepted size, then flatten to opaque RGB.
  #
  # App Store Connect validates dimensions exactly — a one-pixel mismatch is rejected —
  # and it rejects a PNG with an alpha channel too. A simulator capture is RGBA, so both
  # matter here. `sips` cannot drop an alpha channel, hence the PIL pass: the file has to
  # stay PNG (preferred for UI art), so converting to JPEG purely to lose the alpha would
  # trade one spec violation for a worse format choice.
  local i=0
  for f in "$TMP"/0*.png; do
    [ -f "$f" ] || continue
    i=$((i + 1))
    local out h w
    out=$(printf '%s/%02d.png' "$dir" "$i")
    h="${size#*x}"; w="${size%x*}"          # sips takes HEIGHT then WIDTH
    sips -z "$h" "$w" "$f" --out "$out" >/dev/null 2>&1
  done

  # `python3` on PATH is not necessarily an interpreter with PIL: this failed in a
  # background run while succeeding in an interactive shell, because the two resolve
  # different pythons and the Homebrew one has no PIL. Ask for an explicit one, and if
  # neither can do it, fall back to JPEG — App Store Connect accepts PNG or JPEG, and a
  # valid JPEG beats a PNG that gets rejected for its alpha channel.
  if ! "$PY" - "$dir" <<'PY'
import sys
from pathlib import Path
from PIL import Image
for f in sorted(Path(sys.argv[1]).glob("*.png")):
    im = Image.open(f)
    if im.mode != "RGB":
        im.convert("RGB").save(f, "PNG", optimize=True)
PY
  then
    say "  (no PIL — re-encoding as JPEG, which carries no alpha channel)"
    for f in "$dir"/*.png; do
      [ -f "$f" ] || continue
      sips -s format jpeg -s formatOptions 95 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1
      rm -f "$f"
    done
  fi
  say "  -> $i images"
}

ensure_booted() { boot "$1"; }

main() {
  local app; app=$(app_path)
  [ -d "$app" ] || { say "No built app at $app — build first."; exit 1; }
  say "app: $app"

  boot "$IPHONE_UDID"
  xcrun simctl install "$IPHONE_UDID" "$app" >/dev/null 2>&1

  pack "$IPHONE_UDID" "$OUT/iphone-6.9" "$IPHONE_SHOT"
  pack "$IPHONE_UDID" "$OUT/iphone-6.7" "$IPHONE_SHOT_67"

  say ""
  say "=== verify: the size must match to the pixel, and alpha must be off ==="
  local bad=0
  for f in "$OUT"/*/*.png; do
    local w h a
    w=$(sips -g pixelWidth  "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
    a=$(sips -g hasAlpha    "$f" 2>/dev/null | awk '/hasAlpha/{print $2}')
    local want="ok"
    case "$f" in
      *iphone-6.9*) [ "$w $h" = "2868 1320" ] || want="WRONG SIZE" ;;
      *iphone-6.7*) [ "$w $h" = "2796 1290" ] || want="WRONG SIZE" ;;
    esac
    [ "$a" = "no" ] || want="HAS ALPHA"
    if [ "$want" != "ok" ]; then
      say "  $want  $(basename "$(dirname "$f")")/$(basename "$f")  ${w}x${h} alpha=$a"
      bad=$((bad + 1))
    fi
  done
  say "  $(ls "$OUT"/*/*.png 2>/dev/null | wc -l | tr -d ' ') images, $bad problems"

  [ "${1:-}" = "--keep-frames" ] || rm -rf "$TMP"
  [ "$bad" -eq 0 ] || exit 1
}

main "$@"

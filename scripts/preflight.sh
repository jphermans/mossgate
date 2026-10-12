#!/usr/bin/env bash
#
# preflight.sh — is this build actually ready for TestFlight / the App Store?
#
# Run from the repo root, before every archive:
#
#     bash scripts/preflight.sh
#
# Exits 0 when everything is green, non-zero on any failure, and names each failure as it
# goes. Adapted from the ios-app-store-submission skill's ship-ready-check.sh, plus the
# checks this particular app needs.
#
# WHY A SCRIPT AND NOT A CHECKLIST: every item below is a thing that only fails at upload
# time, which is the worst moment to learn it — you are mid-submission with an archive
# built and a listing half-filled. This asserts the same facts in one command instead.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

PROJECT="Mossgate"
SCHEME="Mossgate"
TARGET="Mossgate"
IOS_DIR="ios"
# Two different directories, and conflating them is what broke the first version of this
# script: the project is ios/Mossgate.xcodeproj, while the sources and assets live in
# ios/Mossgate/. Appending the project name to the source dir produced a path that does not
# exist, so the builds silently "failed" and every check depending on a built .app followed.
XCODEPROJ="$IOS_DIR/$PROJECT.xcodeproj"
SRC_DIR="$IOS_DIR/$PROJECT"
SUPPORT_URL="https://jphermans.github.io/mossgate-support/"

fail=0
say()  { printf '%s\n' "$*"; }
ok()   { say "  ok    $*"; }
miss() { say "  MISS  $*"; fail=$((fail + 1)); }

# ── 1. The toolchain ────────────────────────────────────────────────────────────────────
# First, because it is the hardest block and no code change can work around it: Apple
# refuses a binary built with a beta Xcode ("This build is using a beta version of Xcode
# and can't be submitted"). Bumping versions, fixing metadata, re-archiving — none of it
# helps. The only fixes are the current public release or the newest seed listed under App
# Store Connect → News and Updates → Releases.
say "=== Toolchain ==="
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1)
case "$XCODE_VER" in
  *[Bb]eta*|*[Ss]eed*|*[Rr]elease*[Cc]andidate*|*RC*)
    miss "$XCODE_VER — a pre-release Xcode. App Store Connect will reject the upload." ;;
  *)
    ok "$XCODE_VER" ;;
esac

# ── 2. Builds ───────────────────────────────────────────────────────────────────────────
say "=== Debug simulator build ==="
if xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" \
      -sdk iphonesimulator -configuration Debug \
      CODE_SIGNING_ALLOWED=NO build 2>&1 \
      | grep -E 'error:|SUCCEEDED' | grep -v 'swiftc ' | grep -q 'SUCCEEDED'; then
  ok "Debug iphonesimulator"
else
  miss "Debug iphonesimulator build failed"
fi

# The simulator build does NOT exercise the App Store path — this is the "would this
# archive?" command, and the only local proof the binary is buildable for submission.
say "=== Release device build (the archive check) ==="
if xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" \
      -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' \
      CODE_SIGNING_ALLOWED=NO clean build 2>&1 \
      | grep -E 'error:|SUCCEEDED' | grep -v 'swiftc ' | grep -q 'SUCCEEDED'; then
  ok "Release iphoneos"
else
  miss "Release iphoneos build failed"
fi

APP=$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -sdk iphoneos \
        -configuration Release -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/$TARGET.app

# ── 3. Version numbers ──────────────────────────────────────────────────────────────────
say "=== Versions ==="
if [ -d "$APP" ]; then
  MARKETING=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" 2>/dev/null)
  BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist" 2>/dev/null)
  SPEC_M=$(grep -E '^\s*MARKETING_VERSION:' "$IOS_DIR/project.yml" | tr -d ' "' | cut -d: -f2)
  SPEC_B=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$IOS_DIR/project.yml" | tr -d ' "' | cut -d: -f2)
  [ "$MARKETING" = "$SPEC_M" ] && ok "MARKETING_VERSION $MARKETING matches project.yml" \
                              || miss "MARKETING_VERSION: built '$MARKETING' vs project.yml '$SPEC_M'"
  [ "$BUILD" = "$SPEC_B" ] && ok "CURRENT_PROJECT_VERSION $BUILD matches project.yml" \
                           || miss "CURRENT_PROJECT_VERSION: built '$BUILD' vs project.yml '$SPEC_B'"
  # TestFlight rejects a build number it has already seen, so this has to strictly increase
  # between uploads. Nothing here can know what has been uploaded — this is the reminder.
  say "  note  build $BUILD must be greater than the last one uploaded"
else
  miss "Release .app not found at $APP — skipping plist checks"
fi

# ── 4. Info.plist keys that decide acceptance ───────────────────────────────────────────
say "=== Info.plist ==="
if [ -d "$APP" ]; then
  P="$APP/Info.plist"
  for k in CFBundleDisplayName MinimumOSVersion LSApplicationCategoryType CFBundleIdentifier; do
    v=$(plutil -extract "$k" raw "$P" 2>/dev/null)
    [ -n "$v" ] && [ "$v" != "null" ] && ok "$k = $v" || miss "$k missing"
  done

  # iPhone only. This is not cosmetic: the device family is what decides whether Apple
  # requires an iPad screenshot set. Claiming "1,2" means building a 13-inch pack.
  fam=$(plutil -extract UIDeviceFamily json -o - "$P" 2>/dev/null | tr -d ' \n')
  [ "$fam" = "[1]" ] && ok "UIDeviceFamily [1] — iPhone only, no iPad set required" \
                     || miss "UIDeviceFamily $fam — iPad support claimed, so an iPad screenshot set is required"

  plutil -p "$P" | grep -q 'UIRequiresFullScreen' \
    && miss "UIRequiresFullScreen present (deprecated since iOS 26; Apple has rejected binaries carrying it)" \
    || ok "no deprecated UIRequiresFullScreen"

  enc=$(plutil -extract ITSAppUsesNonExemptEncryption raw "$P" 2>/dev/null)
  [ "$enc" = "false" ] || [ "$enc" = "0" ] \
    && ok "ITSAppUsesNonExemptEncryption = false" \
    || miss "ITSAppUsesNonExemptEncryption not declared — every upload stops for a compliance question"

  # The game is landscape, but the splash is portrait and it has always launched correctly,
  # so this asserts the set exists rather than insisting on a particular count.
  ori=$(plutil -extract UISupportedInterfaceOrientations json -o - "$P" 2>/dev/null)
  [ -n "$ori" ] && ok "orientations declared: $(printf '%s' "$ori" | tr -d ' \n')" \
                || miss "no UISupportedInterfaceOrientations"
fi

# ── 5. PrivacyInfo ──────────────────────────────────────────────────────────────────────
# Required since May 2024, and required to be IN the bundle. The per-key checks matter:
# `grep NSPrivacyTracking` also matches `NSPrivacyTrackingDomains`, and a quoted key with
# `=>` in plutil output defeats a naive pattern.
say "=== PrivacyInfo.xcprivacy ==="
if [ -f "$APP/PrivacyInfo.xcprivacy" ]; then
  ok "bundled"
  [ "$(plutil -extract NSPrivacyTracking raw "$APP/PrivacyInfo.xcprivacy" 2>/dev/null)" = "false" ] \
    && ok "NSPrivacyTracking false" || miss "NSPrivacyTracking is not false"
  n=$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$APP/PrivacyInfo.xcprivacy" 2>/dev/null | tr -d ' \n')
  [ "$n" = "[]" ] && ok "no collected data types" || miss "NSPrivacyCollectedDataTypes is not empty"
  d=$(plutil -extract NSPrivacyTrackingDomains json -o - "$APP/PrivacyInfo.xcprivacy" 2>/dev/null | tr -d ' \n')
  [ "$d" = "[]" ] && ok "no tracking domains" || miss "NSPrivacyTrackingDomains is not empty"
else
  miss "PrivacyInfo.xcprivacy missing from the bundle"
fi

# ── 6. ExportOptions ────────────────────────────────────────────────────────────────────
say "=== ExportOptions.plist ==="
if [ -f "$IOS_DIR/ExportOptions.plist" ]; then
  if grep -q 'YOUR_TEAM_ID' "$IOS_DIR/ExportOptions.plist"; then
    miss "teamID is still the YOUR_TEAM_ID placeholder. THIS ONE IS YOURS, not the code's. It only affects the scripted export (xcodebuild -exportArchive) — Xcode's Organizer upload ignores this file entirely — so set it before using the command-line path."
  else
    ok "present with a teamID set"
  fi
else
  miss "missing (needed for xcodebuild -exportArchive)"
fi

# ── 7. App icon ─────────────────────────────────────────────────────────────────────────
say "=== App icon ==="
ICONSET="$SRC_DIR/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET" ]; then
  master=$(ls "$ICONSET"/*.png 2>/dev/null | head -1)
  if [ -n "$master" ]; then
    w=$(sips -g pixelWidth "$master" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$master" | awk '/pixelHeight/{print $2}')
    a=$(sips -g hasAlpha "$master" | awk '/hasAlpha/{print $2}')
    [ "$w" = "1024" ] && [ "$h" = "1024" ] && ok "1024x1024 master" || miss "master is ${w}x${h}, must be 1024x1024"
    [ "$a" = "no" ] && ok "hasAlpha no" || miss "hasAlpha yes — the icon must be opaque RGB"
  else
    miss "no PNG in AppIcon.appiconset"
  fi
else
  miss "AppIcon.appiconset missing"
fi

# ── 8. Screenshot packs ─────────────────────────────────────────────────────────────────
# Sizes must match to the pixel, alpha must be off, and the pack must hold 3-10 images.
# Regenerate with scripts/capture-shots.sh.
say "=== Screenshots ==="
for dir in AppStore/Screenshots/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  case "$name" in
    iphone-6.7) want="2796 1290" ;;
    iphone-6.9) want="2868 1320" ;;
    *) say "  note  $name — not a pack size this check knows"; continue ;;
  esac
  # Accept PNG or JPEG: both are allowed, and the rig falls back to JPEG when PIL is absent.
  count=$(ls "$dir"*.png "$dir"*.jpg 2>/dev/null | wc -l | tr -d ' ')
  bad=0
  for f in "$dir"*.png "$dir"*.jpg; do
    [ -f "$f" ] || continue
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
    [ "$w $h" = "$want" ] || bad=$((bad + 1))
  done
  if [ "$count" -lt 3 ] || [ "$count" -gt 10 ]; then
    miss "$name has $count images (must be 3-10)"
  elif [ "$bad" -gt 0 ]; then
    miss "$name: $bad image(s) not ${want// /x}"
  else
    ok "$name: $count images at ${want// /x}"
  fi
done

# ── 9. The URLs Apple re-checks after submission ────────────────────────────────────────
say "=== Support and privacy URLs ==="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$SUPPORT_URL")
[ "$code" = "200" ] && ok "$SUPPORT_URL answers 200" || miss "$SUPPORT_URL answers $code"
if [ -d "$APP" ]; then
  V=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" 2>/dev/null)
  if curl -s --max-time 20 "$SUPPORT_URL" | grep -q ">$V<"; then
    ok "the page names the version being submitted ($V)"
  else
    miss "the support page does not mention $V — publish the release notes before submitting"
  fi
fi

# ── 10. A clean tree ────────────────────────────────────────────────────────────────────
say "=== Working tree ==="
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  ok "clean"
else
  miss "uncommitted changes — the archive will not match what is in the repo"
fi

# ── Verdict ─────────────────────────────────────────────────────────────────────────────
say ""
if [ "$fail" -eq 0 ]; then
  say "READY — nothing above blocks an archive."
  exit 0
fi
say "NOT READY — $fail item(s) above. Fix them before archiving."
exit 1

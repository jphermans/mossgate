# Shipping Mossgate to TestFlight and the App Store

This covers the engineering side, which is finished and verified, and the account side, which
needs your Apple ID and cannot be done from this repo.

Two things to know before anything else:

1. **Check the toolchain before you archive.** Apple refuses a binary built with a beta Xcode —
   "This build is using a beta version of Xcode and can't be submitted" — and no code change
   works around it. Only a current public Xcode release, or the newest seed Apple lists under
   App Store Connect → News and Updates → Releases, will do.
   **As of this writing `xcodebuild -version` reports Xcode 27.1, which is a release build and
   is fine.** Confirm it before every archive, and make sure a leftover beta install is not the
   selected toolchain — `xcode-select -p` names the active one.
2. **The app is iPhone-only**, by decision. No iPad screenshot set is required, and
   `TARGETED_DEVICE_FAMILY` is `"1"`. The app still installs on iPad in compatibility mode;
   that is not the same as supporting it.

If anything here contradicts Apple's current guidelines or App Store Connect Help, Apple wins.

---

## 1. What's already done

Verified in the build, not assumed:

| | |
|---|---|
| Bundle identifier | `io.jphsystems.mossgate` |
| Display name | Mossgate |
| Version | **0.7.34 (build 57)** — `ios/project.yml` is the single source |
| iOS deployment target | 18.0 |
| Device family | iPhone (`"1"`) |
| Orientation | landscape, both ways; portrait splash |
| Category | `public.app-category.games` |
| Third-party dependencies | none — no SPM packages, nothing to embed or license |
| Network use | none — the app makes no network calls at all |
| Sign-in / accounts | none |
| Encryption | `ITSAppUsesNonExemptEncryption = false` |

**PrivacyInfo.xcprivacy** is bundled and declares no tracking, no collected data types and no
tracking domains. Privacy nutrition labels in App Store Connect therefore reduce to "Data Not
Collected", which is the honest answer for a game that never sends anything anywhere.

**The app icon** is a 1024×1024 opaque master with iOS 26 light, dark and tinted appearances.

**Screenshots** are in `AppStore/Screenshots/iphone-6.7/` — six landscape frames at 2796×1290,
verified opaque. Regenerate after any visible change with:

```bash
bash scripts/capture-shots.sh      # captures, resizes, verifies; exits non-zero if wrong
```

**`ios/ExportOptions.plist`** is checked in for the archive → export step. Its `teamID` is a
placeholder — set it to your real 10-character team ID before exporting (see § 3.1).

---

## 2. Preflight — run this before every archive

```bash
bash scripts/preflight.sh
```

It asserts everything below in one command and exits non-zero on any failure: the toolchain
(the beta check from the top of this document), both builds including the Release device build
that is the only local proof the app would archive at all, version numbers agreeing between
`ios/project.yml` and the built plist, the device family, the deprecated-`UIRequiresFullScreen`
check, the encryption declaration, the privacy manifest's per-key values, the icon's size and
opacity, the screenshot packs, the support page actually answering and naming the version being
submitted, and a clean working tree.

Every one of those is something that otherwise fails *during* submission, with an archive built
and a listing half-filled. Running it first is the whole point.

---

## 3. Before the first archive

### 3.1 Signing
Open `ios/Mossgate.xcodeproj` → target Mossgate → **Signing & Capabilities**:

- **Team**: your Apple Developer team. This is the ID `ExportOptions.plist` needs.
- **Bundle identifier**: `io.jphsystems.mossgate` — must be registered as an App ID (§ 4.1).
- Signing style automatic; Xcode creates the distribution profile at archive time.

### 3.2 Game Center needs the capability turned ON, and its IDs created
`GameCenterManager.swift` is wired: clearing a gate reports achievements and submits two
leaderboards, and the title screen's Game Center button opens the dashboard. The calls are
already in the game — completing a gate is what reports.

It reports nothing until an App ID capability exists and the identifiers are registered, so:

- **Capability**: developer.apple.com → Identifiers → `io.jphsystems.mossgate` → tick
  **Game Center** → Save. Game Center needs no entitlement and no Info.plist key, so there is
  nothing to change in this repo — the capability is the whole switch.
- **Identifiers**: enter these in App Store Connect → your app → Game Center. They must match
  `GameCenterManager.ID` **character for character**. A mismatch is not an error anywhere: the
  SDK accepts the report and matches it against nothing, so the failure is invisible.

  Achievements — `io.jphsystems.mossgate.first_clear`, `.all_coins_level`, `.world_1_cleared`,
  `.world_2_cleared`, `.no_death_run`
  Leaderboards — `.total_coins`, plus one per gate, `.level_<id>_best`, for `<id>` 0 through 35.

  The per-gate set is 36 leaderboards; generate them rather than typing them, and keep the same
  numbering as `Levels`, because the app submits `level.id` straight into that name.

Until the capability is on, the game is unaffected: every report no-ops and the dashboard button
simply re-attempts sign-in.

### 3.3 Do not run `xcodegen` by hand expecting different results
`ios/project.yml` is the single source of truth for the project; `scripts/bump-ios-version.py`
regenerates the `.xcodeproj` after bumping. Editing the project in Xcode's GUI can silently
truncate values that only exist in the yml — the version numbers and the orientation list have
both been lost that way before. Change the yml, then let the bump script regenerate.

---

## 4. App Store Connect setup (your account)

### 4.1 Register the App ID
<https://developer.apple.com/account/resources/identifiers/list> → **+** → App IDs → App.

- Bundle ID: **explicit**, `io.jphsystems.mossgate`
- Capabilities: **Game Center** only — see § 3.2. No push, no app groups, no keychain sharing.
- If the App ID already exists, use it — do not recreate it.

### 4.2 Create the app record
<https://appstoreconnect.apple.com/> → My Apps → **+** → New App.

- Platform iOS, name **Mossgate**, primary language English
- Bundle ID: the one above
- SKU: any unique string, e.g. `mossgate-ios-001`

### 4.3 The in-app purchase
The game sells the full 5-of-6 worlds for $2.99 from inside the app.

1. App Store Connect → your app → **Monetization → In-App Purchases** → **+**
2. Type **Non-Consumable** (it is a one-time unlock, and must stay unlocked across restores)
3. Product ID: **`com.jphsystems.mossgate.fullgame`** — must match `Store.swift` exactly, or the
   store sits on "Loading…" forever
4. Price: Tier 3 ($2.99)
5. Display name and description as the user sees them in the purchase sheet
6. **Add a screenshot of the purchase screen** — the IAP cannot be reviewed without one
7. Submit it **with** the app version, not separately, so the first review covers both

Test locally first with a sandbox account: Settings → App Store → Sandbox Account on a real
device. The simulator cannot complete a real purchase.

### 4.4 TestFlight
Internal testing works as soon as a build is processed — up to 100 testers on your team, no
review. External testing needs a short review and builds expire after 90 days.

---

## 5. Archiving and uploading

```bash
cd ios
xcodebuild -project Mossgate.xcodeproj -scheme Mossgate \
  -sdk iphoneos -configuration Release \
  -destination 'generic/platform=iOS' clean archive \
  -archivePath ../build/Mossgate.xcarchive
```

Or in Xcode: **Any iOS Device (arm64)** → Product → Archive → Distribute App → App Store
Connect → Upload. Keep *upload symbols* on — Apple needs them to symbolicate TestFlight crash
logs, and a crash report full of addresses is not worth having.

The build number must strictly increase for every upload; App Store Connect rejects a
`CFBundleVersion` it has already seen. `scripts/bump-ios-version.py` bumps both numbers and
regenerates the project.

Processing takes 5–30 minutes. You get an email when the build is ready.

---

## 6. The listing

**Screenshots** — upload `AppStore/Screenshots/iphone-6.7/01.png` … `06.png`. Six frames at
2796×1290: gameplay in four worlds, the guide screen, and the free Daily Gate.

**Description** — lead with what the game is, not with the brand. A player deciding whether to
download cares that it is a dusk-lit platformer where the lantern has to reach the gate, not
that it was made by JPHsystems.

**Keywords** (100 characters, comma-separated, no spaces needed after commas):
`platformer,indie game,retro,dusk,pixel,dungeon,adventure,runner,puzzle,offline,single player,lantern`

**Support URL**: <https://jphermans.github.io/mossgate-support/>
**Privacy policy URL**: <https://jphermans.github.io/mossgate-support/#privacy>
**Marketing URL**: optional

**App Privacy**: "Data Not Collected". The manifest already says so; do not claim otherwise.

### App Review notes — put this in the box

> Mossgate is a landscape-only platformer game for iPhone. All content is bundled in the app;
> it makes no network requests and requires no account or sign-in.
>
> The first world is free. The remaining five are unlocked by a single non-consumable in-app
> purchase, `com.jphsystems.mossgate.fullgame` ($2.99), attached to this version.
>
> Controls: on-screen left/right, jump (tap twice to double-jump), and up/down to look around —
> or a Bluetooth game controller.
>
> Every level is procedurally varied per run, so a reviewer may see a slightly different layout
> than the screenshots show; the art, mechanics and difficulty are identical.

---

## 7. Things that get games rejected

- **Landscape-only confusion.** The splash is portrait and gameplay is landscape. That is
  intentional and has always worked; do not "fix" the orientation list.
- **A store that never loads.** The IAP product ID must match `Store.swift` character for
  character, and the product has to exist in App Store Connect before purchase buttons respond.
- **Placeholder anything.** Grep before submitting — no lorem ipsum, no `example.com`, no
  "TODO" reaching a user-visible string.
- **"Rate this app" pointing nowhere.** The About screen's rate row needs the App Store ID,
  which does not exist until the app is live. Wire it after the first release.
- **A beta Xcode.** See the top of this document. It is the one blocker no code change fixes.

---

## 8. What this document does not do

It does not register a developer account, generate marketing copy, upload builds, or answer
App Review. Those need credentials and judgement that are yours. The code, the assets, the
build configuration, the privacy manifest, the export options, the screenshots and the
preflight script are all in place.

---
name: verify-when-is-bin
description: Launch, health-check, drive and capture evidence from the real When Is Bins Flutter app (iOS Simulator via flutter drive; Jess's iPhone for release builds) against the live WhenIsBins API, to prove onboarding, bin-day lookups and reminders work for a user. Use before claiming a feature or fix in When Is Bins works, or when asked to verify, reproduce or screenshot When Is Bins behaviour.
---
<!-- Generated with /create-verification-skill (adapted from pstack by Lauren Tan, MIT licence) -->

# Verify When Is Bins

Read cold: this skill assumes nothing about the app beyond what is written here. Features to drive are in [features/README.md](features/README.md); read the index, then the matching feature file.

The app: UK bin-day reminders. A postcode goes to the WhenIsBins API (`GET /addresses`), the council decides what else it needs (an address picked from a list, a typed first line, nothing at all), a lookup (`POST /lookups`, then a long-poll) returns the schedule, and onboarding ends with "Turn on reminders" (iOS notification permission, then one local notification per upcoming collection, 9am or 7pm the day before, Europe/London). State lives in SharedPreferences; there is no account and no backend of Jess's own.

- iOS bundle ID `com.jessicamumby.whenIsBinApp`; Android `com.jessicamumby.when_is_bin_app`.
- Build stamp: Settings ends with `Build <sha>` when built with `--dart-define=GIT_SHA=<short sha>`; `Build dev` means no define.
- Live on the App Store. The live API (`whenisbins.com`) is the only backend: there is no staging, and anonymous use is rate limited per IP.

## Run directory

Every run writes to `RUN_DIR=<repo root>/.verify-runs/<yyyymmdd-hhmmss>-<feature>` (gitignored; absolute path, because the driver writes screenshots there) and records what it started in `$RUN_DIR/started.txt`, one line per thing: `sim <udid>` (only if this run booted it), `pid <pid> <what>`, `recorder <pid>`, `app <udid> <bundle-id>` (an app instance the run left running). Cleanup reads that file. Evidence stays in `$RUN_DIR`; copy it out before removing a worktree, because the folder goes with it.

```bash
cd "$(git rev-parse --show-toplevel)"
FEATURE=onb-postcode-only            # the feature ID you are driving
RUN_DIR="$PWD/.verify-runs/$(date +%Y%m%d-%H%M%S)-$FEATURE"; mkdir -p "$RUN_DIR"; : > "$RUN_DIR/started.txt"
```

## Helpers (`scripts/`, all executable)

| Script | Invocation | Does |
|---|---|---|
| `doctor.sh` | `scripts/doctor.sh "$UDID"` | read-only freshness and device check (Doctor) |
| `tap_system_button.sh` | `[TAP_DELAY=s] scripts/tap_system_button.sh "$UDID" <label> [timeout] [dir]` | taps an iOS alert button by its visible label (Drive) |
| `ocr.swift` | built by `tap_system_button.sh`; then `"$TMPDIR/verify-when-is-bin-ocr" <png>` | prints the text Vision reads in a screenshot, with pixel centres |
| `find_postcode_only.sh` | `[MAX_WAIT=s] scripts/find_postcode_only.sh "<postcode>" ...` | read-only `GET /addresses` probe for a postcode-only council (onboarding feature) |
| `cleanup.sh` | `scripts/cleanup.sh "$RUN_DIR"` | stops what `started.txt` lists, keeps the evidence (Cleanup) |

Paths are relative to `.claude/skills/verify-when-is-bin/`.

## Launch

Rung 1 (iOS Simulator, debug). Use one simulator you own for the whole run; never drive one another agent or Jess booted.

```bash
[ -f .env ] || cp .env.example .env    # .env is a declared Flutter asset; never overwrite a real one
flutter pub get
UDID=<simulator udid>                  # e.g. iPhone 17 Pro; list: xcrun simctl list devices available
xcrun simctl list devices booted | grep -q "$UDID" || echo "sim $UDID" >> "$RUN_DIR/started.txt"
xcrun simctl bootstatus "$UDID" -b     # boots if needed, waits until ready
open -a Simulator --args -CurrentDeviceUDID "$UDID"   # its window must be visible for tap_system_button.sh
```

There is no long-lived app instance: each drive is one `flutter drive` that builds, installs, starts the real `main()` and exits (see Drive). Ready = the drive log prints its first `VERIFY state` line. Teardown = Cleanup.

Rung 2 (release) needs Jess's iPhone: see [Physical iPhone](#physical-iphone-rung-2-only-with-jesss-consent). The iOS Simulator cannot run release builds.

## Doctor

```bash
.claude/skills/verify-when-is-bin/scripts/doctor.sh "$UDID" | tee "$RUN_DIR/doctor.log"
```

Read-only apart from `git fetch`. It must print:

- `branch=... head=<sha> origin/main=<sha> ahead=N behind=0`. Behind > 0 prints `REFUSE` and exits 1: do not build. Rebase or merge `origin/main` first, or set `ALLOW_BEHIND=1` only when Jess said to verify an older build.
- `uncommitted_files=0`, or the verdict's Build line says `+uncommitted`.
- `.env present`, `api_host=whenisbins.com` (anything else: say so in the verdict), `api_token=set|empty` (value never shown; empty is fine for a drive or two, see Gotchas).
- `simulator <udid> booted`, and whether the app is installed.
- the physical iPhone row if one is reachable (informational on rung 1).
- `doctor_exit=0`.

Run doctor before the first drive, after any failed drive, and whenever something looks off.

## Drive

Harness: `integration_test` driven by `flutter drive` (rung 1). Drives live in `integration_test/verify/<feature>_test.dart`, shared helpers in `integration_test/verify/support.dart`, the screenshot-writing driver in `test_driver/integration_test.dart`. They are verification scaffolding: the app never imports them and CI's `flutter test` does not run them.

```bash
( set -o pipefail; RUN_DIR="$RUN_DIR" flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/verify/<feature>_test.dart -d "$UDID" --keep-app-running \
  --dart-define=GIT_SHA=$(git rev-parse --short HEAD) [--dart-define=VERIFY_POSTCODE='<postcode>'] \
  2>&1 | tee "$RUN_DIR/drive.log" ); echo "exit=$?" >> "$RUN_DIR/drive.log"
echo "app $UDID com.jessicamumby.whenIsBinApp" >> "$RUN_DIR/started.txt"
grep -E '^flutter: VERIFY|All tests passed|Some tests failed|^exit=' "$RUN_DIR/drive.log"
```

`--keep-app-running` matters: without it `flutter drive` uninstalls the app when the test ends, taking the stored values and the after-relaunch state with it. The instance it leaves running is the test binding's, frozen mid-frame, not a normal launch: never screenshot or read prefs from it. Stop it first (Evidence shows how).

Every drive prints `VERIFY action ...` and `VERIFY state ...` lines: those are the action/result pairs to quote. A failure reason starts `PRECONDITION:` (arrange it and drive again) or `BEHAVIOUR:` (the app did the wrong thing: NOT VERIFIED).

The app has no Keys or Semantics identifiers. Selectors are visible copy (`find.text('Find my bin day')`), scoped to the screen that owns it (`inOnboarding(...)`, `inAddressForm(...)` in `support.dart`), because onboarding stays mounted under the address form with its own button of the same name. Never use widget indexes or coordinates inside a drive.

OS alerts (the notification permission prompt) are outside Flutter. Answer them as a user would, from the host, with:

```bash
.claude/skills/verify-when-is-bin/scripts/tap_system_button.sh "$UDID" Allow 300 "$RUN_DIR" > "$RUN_DIR/tap.log" 2>&1 &
echo "pid $! tap_system_button" >> "$RUN_DIR/started.txt"
```

Start it just before the drive, in the same shell, so it outlives the build. It finds and raises the Simulator window titled for that UDID, polls simulator screenshots until Vision OCR (`scripts/ocr.swift`, compiled once to `$TMPDIR/verify-when-is-bin-ocr`) finds a line exactly equal to the label, clicks it with System Events, and confirms the label has gone. Coordinates come from a fresh screenshot each time. It needs Accessibility permission for the terminal and the simulator window visible on the current Space; `simctl privacy` cannot grant notifications. Measured on 5 October 2026: the Allow lands about 8 seconds after the alert appears, which is after the app's 5 second permission wait (see the reminders feature). `TAP_DELAY=<s>` adds a deliberate pause. It is for OS alerts only: System Events clicks reach iOS alerts and SpringBoard, but did not register on Flutter content, so drive the app itself from the test.

Rules: real user actions only; arrange preconditions (fresh install, a suitable postcode, permission answers), never inject the symptom or outcome; stable handles, never coordinates without a fresh screenshot; no secrets in logs or artefacts.

## Evidence

- Flutter-surface screenshots: `binding.takeScreenshot` in each drive, written by the driver to `$RUN_DIR/<prefix>-<n>-<state>.png` when the drive ends. They do not show OS alerts.
- Whole-screen screenshots (alerts, after relaunch): `xcrun simctl io "$UDID" screenshot "$RUN_DIR/<feature>-<state>.png"`.
- Recording (optional): `xcrun simctl io "$UDID" recordVideo "$RUN_DIR/<feature>.mp4" & echo "recorder $!" >> "$RUN_DIR/started.txt"`; stop with `kill -INT <pid>`. No real personal data is on screen with the test postcodes.
- After relaunch, then stored values, read-only. Relaunch replaces the frozen test instance with a normal launch; the plist is only trustworthy after a terminate that succeeded (a read while the test instance was alive showed a stale `reminders_enabled => false` that the relaunched app contradicted). Keys carry the `flutter.` prefix:

  ```bash
  B=com.jessicamumby.whenIsBinApp
  xcrun simctl launch --terminate-running-process "$UDID" $B; sleep 8
  xcrun simctl io "$UDID" screenshot "$RUN_DIR/<feature>-relaunch.png"
  xcrun simctl terminate "$UDID" $B && sleep 1
  C=$(xcrun simctl get_app_container "$UDID" $B data)
  plutil -p "$C/Library/Preferences/$B.plist" | grep -E '"flutter\.(onboarded|saved_address|saved_postcode|reminders_enabled|reminder_time)"' | tee "$RUN_DIR/prefs.txt"
  ```

- Pending notifications: the drive asks iOS (`UNUserNotificationCenter`, through the plugin's read-only `pendingNotificationRequests()`) and logs one `VERIFY pending id=...` line per request. That is the OS's list, not the app's. No host-side file holds it on the iOS 26 simulator (searched `data/Library/UserNotifications` on 5 October 2026), so don't look for one.
- Text on a host screenshot: `"$TMPDIR/verify-when-is-bin-ocr" <png> | cut -f1` prints every line Vision reads, a quick check that a capture shows what you claim.
- Build identity: the drive passes `--dart-define=GIT_SHA=<doctor head>`; Settings shows `Build <sha>`. A debug simulator build also shows the red DEBUG banner, which tells it apart from the App Store build. Screenshot Settings when the feature passes through it; otherwise build identity rests on the doctor log plus the drive's own build.

## Cleanup

```bash
.claude/skills/verify-when-is-bin/scripts/cleanup.sh "$RUN_DIR"
```

It stops only what `started.txt` lists (helper processes, recorders, apps it launched, then simulators this run booted), never kills by name, never erases a simulator, leaves `.env` and the installed debug app in place, and ends by listing `$RUN_DIR` to prove the evidence survived. Report what it stopped and what it retained. Run it after every failed iteration too.

## Verdict

End every run with:

```
VERDICT: VERIFIED | NOT VERIFIED | INCONCLUSIVE
Feature: <feature id(s) and entry points driven>
Build: <branch> @ <short SHA>[+uncommitted], <debug|release> on <device>; backend whenisbins.com
Build stamp seen in app: <SHA from a Settings screenshot, or "not captured: DEBUG banner + doctor head only">
Evidence: <absolute screenshot/recording/log paths>
Stored value read back: <key = value, and how it was read>
Notes: <blocker, skipped entry points, translated evidence, postcode used, release proof pending>
```

VERIFIED = doctor passed on the intended build, real user path driven, discriminating state captured, stored value read back agrees. NOT VERIFIED = driven correctly, behaviour absent or wrong (name the step and the observed state). INCONCLUSIVE = could not drive or could not prove (doctor refused, rate limited, council lookup too slow, alert not answerable, cross-check missing); never round up.

When Is Bins is live with real users: to call a change ready to ship, it needs the release rung (Jess's iPhone); a debug-only proof of a change is INCONCLUSIVE with "release proof pending". A rung-1 baseline check of existing behaviour that Jess asked for on the simulator may be VERIFIED, with the rung in the Build line and "release proof pending" in Notes.

## Physical iPhone (rung 2, only with Jess's consent)

Jess's paired iPhone 17e, UDID `00008150-000A0011029B401C`. Never run this section without Jess saying yes in this conversation, and say first, in one line: "This installs a local release build of When Is Bins over the App Store copy on your iPhone; it replaces that app until you reinstall from the App Store, and onboarding or reminders I drive will change what it shows."

```bash
xcrun devicectl list devices | grep 00008150-000A0011029B401C   # must be "available (paired)" or "connected"; phone unlocked, Developer Mode on
SHA=$(git rev-parse --short HEAD)
flutter build ios --release --dart-define=GIT_SHA=$SHA
flutter install --release -d 00008150-000A0011029B401C
xcrun devicectl device process launch --device 00008150-000A0011029B401C com.jessicamumby.whenIsBinApp
```

- Drive by hand: print the feature file's user-path steps for Jess (integration_test cannot drive a release build), and capture after each discriminating state: `xcrun devicectl device capture screenshot --device 00008150-000A0011029B401C --destination "$RUN_DIR/<feature>-<state>.png"`. If `capture` is missing, Jess screenshots and AirDrops; record it as human-captured.
- Build identity: Settings must show `Build $SHA` and no DEBUG banner before anything counts.
- Stored values: `xcrun devicectl device copy from --device 00008150-000A0011029B401C --domain-type appDataContainer --domain-identifier com.jessicamumby.whenIsBinApp --source Library/Preferences/com.jessicamumby.whenIsBinApp.plist --destination "$RUN_DIR/prefs.plist" && plutil -p "$RUN_DIR/prefs.plist"`. It may refuse for a release-signed build; then the cross-check is the app's own UI (Settings, the reminder card) and the verdict says so.
- To restore: Jess reinstalls When Is Bins from the App Store. Never uninstall it for her.

## Gotchas

- The live API is the only backend, and anonymous use is rate limited per IP, which the simulator shares. On 5 October 2026 about 15 requests earned a 40 minute `Retry-After`, and about 35 in the day (probes plus three onboarding drives, each with a long-poll lookup) earned 81893 seconds, blocking every API drive until the next day. Probe sparingly (`scripts/find_postcode_only.sh` stops on a long wait), prefer the fixture drive where the API is not under test, and ask Jess for a WhenIsBins token in `.env` (never print it).
- Council answers change. A postcode that was postcode-only last month may list addresses today (Cambridge CB4 2HX did), and a council whose site is down sits on the address form for the app's whole lookup budget with no message. Re-check the postcode before a drive; the feature file says how.
- Onboarding only shows on first launch, and the notification permission outlives an uninstall on the simulator. Reset = `xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp` on a simulator you own (verified: the next drive logs `allowed=false`). Never do this on Jess's iPhone.
- Without `--keep-app-running`, `flutter drive` uninstalls the app at the end; with it, the app left behind is the frozen test instance. Either way "after relaunch" needs `xcrun simctl launch --terminate-running-process` and a host screenshot.
- Simulator, not the store build: the DEBUG banner and `Build <sha>` tell them apart; the App Store build shows a SHA with no banner.
- Several agents may share one Mac. Only touch your UDID; `tap_system_button.sh` targets the window by exact title for that reason.

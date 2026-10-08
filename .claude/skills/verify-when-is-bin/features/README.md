# When Is Bins verification map

This directory is the maintained source for verifying the user-facing behaviour of When Is Bins, a Flutter app for UK bin-day reminders backed by the live WhenIsBins API. Read the index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- `scripts/doctor.sh "$UDID"` passes in this run: not behind `origin/main`, `.env` present, `api_host=whenisbins.com`, the simulator booted.
- Rung 1: an iOS Simulator you own for the run (iPhone 17 Pro class, iOS 26), debug build, driven by `flutter drive` with `--dart-define=GIT_SHA=<doctor head>`. Rung 2: Jess's iPhone 17e, release build, driven by hand, only with her consent (see SKILL.md).
- First-launch state: the app uninstalled and its privacy reset on that simulator before each drive (`xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp`).
- Drives run with `--keep-app-running` (otherwise `flutter drive` uninstalls the app at the end); relaunch with `xcrun simctl launch --terminate-running-process` before any host screenshot or prefs read.
- No account, no test credentials: the app has none. The API is anonymous unless Jess put a token in `.env`; budget for its per-IP rate limit (roughly 35 requests a day were allowed on 5 October 2026). Prefer a drive that arranges a saved schedule when the API is not what is under test.
- A postcode whose council fits the feature, re-checked today (councils change their answers). Feature files name one and say how to find another.
- Never drive an instance that was not started or doctor-checked by this run.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise.
- Selectors are visible copy scoped to the owning screen (`inOnboarding`, `inAddressForm`); the app has no Keys or Semantics identifiers yet. Never widget indexes or coordinates in a drive; host taps on OS alerts go through `scripts/tap_system_button.sh`, which locates the label on a fresh screenshot.
- Treat every command as literal. Keep quoted names and flags unchanged.
- Restore state after a mutation (uninstall resets everything on a simulator). Do not remove proof artefacts during cleanup.

## Proof and skip reporting

- Capture the user action and the resulting state, not only the final screen: quote the drive log's `VERIFY action` / `VERIFY state` lines.
- UI proof includes a screenshot with the app identity visible (DEBUG banner on rung 1; `Build <sha>` in Settings when captured).
- Drive proof includes the command, `drive.log` and its `exit=` line.
- Mutation proof includes a read-only second view of the stored value (prefs plist after a clean relaunch, iOS's pending list read by the drive).
- Record the feature ID and entry point used with every artefact.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Features

- [Postcode-only onboarding](./onboarding-postcode-only.md) (`onb-postcode-only`): a council that needs nothing beyond the postcode gets the field-less address form, then the reminder step, then the bin days; persists across relaunch.
- [Reminders after the permission grant](./reminders-after-permission.md) (`rem-after-grant`, `rem-switch-after-grant`): turning on reminders (onboarding button or the bin-days switch) and allowing notifications leaves pending local notifications in iOS; covers the late-Allow case.
- [Bin days, settings and saved address](./settings-and-saved-address.md) (`set-*`): the saved schedule on relaunch, the reminder switch and time, the build stamp, and removing the saved address.
- [Schedule re-check: resume and background](./background-refresh.md) (`bg-*`): `Dates last checked` in Settings, the 12-hour rationed re-check on resume, and the daily background task (Android job forced with `adb`; iOS task only on a real iPhone with Xcode attached).

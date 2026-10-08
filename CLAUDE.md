# When Is Bins

UK bin-day reminders: postcode, then address, then the collection schedule from the free WhenIsBins API (operated by Public Digital), with a local notification the day before (9am or 7pm). Independent app, not a Public Digital product. Live on iOS; Android is on the Play closed-testing (alpha) track only. Store copy and App Privacy answers live in `docs/store-listing.md`; queued work lives in `docs/roadmap.md`.

## Stack
Flutter (stable) for iOS and Android. Provider + ChangeNotifier. `http`, `flutter_local_notifications` + `timezone`, `shared_preferences`, `flutter_dotenv`. Android sharing is a `MethodChannel` to a share intent in `MainActivity`, not a plugin (the channel name is pinned in `test/release_config_test.dart`). Layout: `lib/core` (theme tokens, config, build info), `lib/models`, `lib/services` (API client, reminder scheduling and sync), `lib/providers`, `lib/screens`. Tests mirror `lib/` under `test/`, with fakes in `test/fakes/`.

## Run, test, analyse
`.env` is a declared Flutter asset, so every flutter command fails without it:
```bash
cp .env.example .env   # gitignored; leave WHENISBINS_API_TOKEN empty in anything you ship
flutter pub get && flutter analyze && flutter test
```
`integration_test/live_lookup_test.dart` hits the real API on a device and is not part of CI.

## CI
- `.github/workflows/ci.yml`: analyse + test on every push and PR; `release-artifact` builds the Play bundle and asserts the shipped manifest (INTERNET, notification receivers, no exact-alarm permission) and that no API token is bundled.
- `.github/workflows/ios-build.yml`: unsigned `flutter build ios` on macOS, only for PRs touching `ios/**`, `pubspec.*` or workflows (macOS minutes are expensive).

## Release
No release script yet. A release is a `release/x.y.z` PR that bumps `version:` in `pubspec.yaml`. Every build is stamped with `--dart-define=GIT_SHA=$(git rev-parse --short HEAD)` (shown as "Build <sha>" at the foot of Settings):
- Android: `flutter build appbundle --release --dart-define=...`, signed via `android/key.properties` (see the `.example`), uploaded to the alpha track.
- iOS: `flutter build ipa --release --export-options-plist=... --dart-define=...`, then uploaded and submitted with the `asc` CLI.
- Before a release: run /blast-radius over the diff since the last release tag (no tags yet, so use the last `release/*` merge).
- Device verification: follow `.claude/skills/verify-when-is-bin/SKILL.md` (simulator drives, evidence in the gitignored `.verify-runs/`); release builds still need a check on a real device.

## Gotchas (all release-only, all invisible in debug and green tests)
- R8 strips Gson generics: keep `android/app/proguard-rules.pro` wired in, or every `zonedSchedule` fails and no reminder is saved.
- INTERNET must be in `src/main/AndroidManifest.xml`; the debug manifest hides its absence.
- Notification receivers must be declared, or reminders fire into nothing. No `android:taskAffinity=""` on MainActivity (it orphans the permission result and hangs onboarding).
- iOS drops notifications scheduled before permission is granted: reminders re-sync on app resume. Keep it.
- Reminders are pinned to Europe/London; never derive the zone from the device abbreviation (winter "GMT" has no DST).
- Onboarding must never await permission or scheduling unbounded; both are time-limited and wrapped so `markOnboarded()` always runs.
- iOS deployment target is 15.0 (Podfile `post_install` forces it on pods) for Xcode 26+.
- App Store label: Physical Address is NOT used for tracking (5.1.2(i) rejection). Keep it in step with `PrivacyInfo.xcprivacy`.
- Background re-check (`lib/services/background_refresh.dart`): one task id in three places (Dart `BackgroundRefresh.taskId`, Info.plist `BGTaskSchedulerPermittedIdentifiers`, `AppDelegate.swift`); it must be registered in `didFinishLaunching` because UIScene registers plugins too late. WorkManager's foreground service and permissions are stripped in the manifest. While the app runs, the background task hands its work to the app isolate (one writer); on resume the app reloads prefs before syncing reminders. BGTaskScheduler never runs on the iOS Simulator.
- `test/release_config_test.dart` pins most of the above; extend it rather than relying on memory.

## Conventions
- Feature branch + PR, never commit to `main`. Conventional Commits, British English, tests first.
- Domain modelling: for new stateful logic, name the sealed state type first; parse API/JSON once at the boundary (`lib/models`); no `!` or `as` outside parsers.

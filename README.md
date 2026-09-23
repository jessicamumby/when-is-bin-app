# When Is Bin App

Find your UK bin collection days and get a reminder the night before.

A Flutter app for Android and iOS that recreates the [whenisbins.com](https://whenisbins.com/) experience: enter your postcode, pick your address, see which bins go out and when, and get a local notification the evening (or morning) before each collection.

## Features

- **Postcode → address → schedule** lookup via the [WhenIsBins API](https://whenisbins.com/v1/guide)
- **Native notifications** the night before collection — user chooses 9:00am (morning before) or 7:00pm (evening before)
- **Calendar option** — subscribe to your property's public `.ics` calendar feed
- **Saved address** — quick access to your bin days on next launch
- Design system mirrors whenisbins.com (Lexend Deca, ink/teal/aqua/coral palette, square-cornered controls)

## Getting started

### 1. Get an API token

The app talks to the WhenIsBins API directly. Occasional use works without a token, but for regular use request a free token by emailing `hello@whenisbins.com` (tell them your intended use and approximate volume).

### 2. Configure

Copy `.env.example` to `.env` and add your token:

```bash
cp .env.example .env
# edit .env, set WHENISBINS_API_TOKEN=your-token
```

`.env` is gitignored. The app reads `WHENISBINS_BASE_URL` (defaults to `https://whenisbins.com/v1`) and `WHENISBINS_API_TOKEN`.

### 3. Run

```bash
flutter pub get
flutter run
```

## Architecture

Provider + ChangeNotifier, mirroring the structure of the Scroll Books app:

- `lib/core/` — theme (design tokens), app config
- `lib/models/` — `AddressLookup`, `Schedule`, `Collection`, `Lookup`
- `lib/services/` — `WhenIsBinsApi` (HTTP client), `ReminderScheduler`, `NotificationService`
- `lib/providers/` — `LookupProvider` (postcode → address → lookup → poll), `SettingsProvider` (preferences)
- `lib/screens/` — Home, AddressSelect, Schedule, Settings

### API flow

1. `GET /addresses?postcode=…` — resolve the council and required address input
2. `POST /lookups` with an `Idempotency-Key` — start the lookup
3. Poll `GET /lookups/{id}` until `done`/`failed`
4. `GET /schedules/{property_token}` — re-check the stable schedule later (with `If-None-Match`/ETag)

## Testing

```bash
flutter test
flutter analyze
```

Tests are written first (TDD) and cover models, the API client, reminder scheduling, notification content, providers, the home screen, and the platform icon assets (`test/app_icons_test.dart`).

## App icons

Launcher artwork was generated with [Icon Kitchen](https://icon.kitchen/) and is committed verbatim to the platform folders:

- `android/app/src/main/res/mipmap-*/` — legacy `ic_launcher.png` per density, plus the adaptive icon: `mipmap-anydpi-v26/ic_launcher.xml` referencing `ic_launcher_background`, `ic_launcher_foreground` and `ic_launcher_monochrome` (Android 13+ themed icons). Layers keep their alpha channel because they are composited.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — the full iPhone/iPad/CarPlay matrix plus the 1024px marketing icon, described by `Contents.json`.

Two rules when regenerating:

1. **iOS icons must be saved without an alpha channel.** Icon Kitchen emits RGBA PNGs even when every pixel is opaque; App Store Connect rejects icons that carry an alpha channel, so convert them to RGB (`sips -s format png`, or `PIL.Image.convert('RGB')`) before committing. `test/app_icons_test.dart` fails if any iOS icon regains an alpha channel.
2. **Keep the filenames** the `Contents.json` references, and delete the Flutter template `Icon-App-*.png` files.

`flutter test test/app_icons_test.dart` asserts every icon the manifests and asset catalogue reference exists, is a real PNG, and has the pixel size its platform expects.

## CI

GitHub Actions runs `flutter analyze` and `flutter test` on every push and PR (see `.github/workflows/ci.yml`).

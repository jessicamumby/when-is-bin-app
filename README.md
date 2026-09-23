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

Tests are written first (TDD) and cover models, the API client, reminder scheduling, notification content, providers, and the home screen.

## CI

GitHub Actions runs `flutter analyze` and `flutter test` on every push and PR (see `.github/workflows/ci.yml`).

# Bin days, settings and saved address

An onboarded user with a saved address opens straight onto "Your bin days" (next collection, the reminder card, the calendar feed), can switch reminders off and on, change the reminder time in Settings, see which build they are running, and remove the saved address to start again from the search screen.

Mostly mapped, not yet driven. `reminders_switch_after_permission_test.dart` already covers `set-stamp` (Settings via `Change reminder time`, `Build <sha>`), the switch turning on, and `set-relaunch` with its fixture; build further drives on its pattern (arrange the saved schedule through `SettingsProvider` on a fresh install, so no API call is needed) the first time a change touches these screens.

## Sub-features

- `set-relaunch` reopens on "Your bin days" with the saved address after the app is killed.
- `set-switch` turns reminders off (pending notifications cancelled) and on again (rescheduled).
- `set-time` moves reminders between 9:00am and 7:00pm the day before.
- `set-stamp` shows `Build <sha>` at the foot of Settings.
- `set-remove` removes the saved address and falls back to the search screen (`when·is·bins`).

## How to get to it (user POV)

- Launch the app after onboarding: it opens on "Your bin days".
- The settings cog (tooltip `Settings`) in the "Your bin days" app bar, or `Change reminder time` on the reminder card.
- The switch on the "Remind me to put the bins out" card.

## Driving it with flutter drive

Preconditions:

- Baseline from [README](./README.md); doctor passed in this run.
- An onboarded app with a saved address: arrange it in the drive as `reminders_switch_after_permission_test.dart` does (no API), or onboard for real via the [postcode-only onboarding](./onboarding-postcode-only.md) recipe.

- **Relaunch.** After a `--keep-app-running` drive exits: `xcrun simctl launch --terminate-running-process "$UDID" com.jessicamumby.whenIsBinApp`, wait 8 s, `xcrun simctl io "$UDID" screenshot "$RUN_DIR/set-relaunch.png"`. "Your bin days" with the saved postcode or address under it; no onboarding.
- **Switch off.** `tester.tap(find.byType(Switch))` on the reminder card (only one Switch on the screen). The label reads `Reminders off`; `pendingNotificationRequests()` is empty.
- **Switch on.** Tap it again. `Reminders on`; pending requests return (permission must already be allowed, see the reminders feature).
- **Change time.** `tester.tap(find.text('Change reminder time'))`, then `tester.tap(find.text('Morning before (9:00am)'))`. Back on the card: `You'll get a notification at 9:00am on the day before.`
- **Build stamp.** On Settings, `find.textContaining('Build ')` reads `Build <doctor head>`. Screenshot `set-stamp`.
- **Remove address.** On Settings, `tester.tap(find.text('Remove saved address'))`. Settings shows `No address saved.`; back out and the app shows the search screen (`when·is·bins`, `Find my bin day`).
- **Reset.** `xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp`.

States: default, after relaunch, selected (reminder time radio), disabled (switch while scheduling, or `Reminders need a confirmed address.` for a provisional schedule), empty (`No address saved.`). Not applicable: offline and error on these screens (they read the saved copy; the launch re-check fails silently by design), signed out (no accounts).

## Stable selectors

- Visible copy: `Your bin days`, `Remind me to put the bins out`, `Reminders on`, `Reminders off`, `Change reminder time`, `Morning before (9:00am)`, `Evening before (7:00pm)`, `Remove saved address`, `No address saved.`, `Build `.
- Tooltip `Settings` on the app-bar cog (`find.byTooltip('Settings')`).
- `find.byType(Switch)` is acceptable only because the screen has exactly one switch. Proposed product change: `ValueKey('schedule.reminders')` on it.

## Evidence and cross-check

- Screenshots: `set-relaunch.png`, `set-stamp.png` (Settings with `Build <sha>`), and one per mutation.
- Cross-check: prefs plist after a clean relaunch and terminate (`flutter.reminders_enabled`, `flutter.reminder_time` = `morning|evening`, `flutter.saved_address` absent after removal), and the drive's own `pendingNotificationRequests()` lines (count moves with the switch).

## Gotchas

- Removing the address also cancels reminders (the app re-syncs on every settings change); check pending is empty afterwards, don't assume.
- The launch re-check calls the API; when rate limited it fails silently and the screen shows the saved copy. That is correct behaviour, not a pass for "fresh dates".
- `Build dev` means the build had no `--dart-define=GIT_SHA`: not the build doctor checked.

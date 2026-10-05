# Reminders after the permission grant

A user who taps "Turn on reminders" and then allows notifications ends up with one pending local notification per upcoming collection ("Bins out tomorrow", "Put out the <bins> tomorrow.") at 9:00am or 7:00pm the day before, UK time. iOS silently drops notifications scheduled before permission is granted, and the app stops waiting for the permission verdict after 5 seconds, so a user who reads the alert before tapping Allow relies on the app re-syncing reminders when it resumes. That late-Allow case is the one to prove.

## Sub-features

- `rem-after-grant-late` Allow tapped after the app's 5 s wait: reminders still pending (the resume re-sync).
- `rem-after-grant-prompt` Allow tapped straight away: reminders pending.
- `rem-denied` Don't Allow: onboarding still completes and nothing is pending (expected from the onboarding copy and code; not yet driven).
- `rem-relaunch` reminders survive a kill and relaunch (re-derived on launch).
- `rem-switch-after-grant` the "Your bin days" switch, turned on and allowed, leaves one pending reminder per upcoming collection. Drive: `integration_test/verify/reminders_switch_after_permission_test.dart` (no API needed).
- `rem-switch-late-grant` Allow tapped after the switch's 5 s wait: the switch stays off and the snackbar says to turn notifications on in device settings, although the user just did. Observed 5 October 2026; a product gap, not a harness fault (retrying the switch then works).

## How to get to it (user POV)

- Onboarding: the reminder step's "Turn on reminders" (the iOS alert follows).
- After onboarding: the switch on the "Remind me to put the bins out" card ([settings feature](./settings-and-saved-address.md)).
- Granting later in the iOS Settings app, then returning to the app (resume re-sync). Not driven yet.

## Driving it with flutter drive

### Switch entry point (`rem-switch-after-grant`, no API)

The precondition (onboarded, a saved schedule with collections 7 and 14 days out, reminders off) is arranged inside the drive through the app's own `SettingsProvider`, on a fresh install, under a fixture address `Verify fixture (not a real address)` / `ZZ99 9ZZ`. The behaviour under test still comes from the user: the switch tap and the Allow tap. It does not cover the onboarding button; don't report that entry point from this drive.

```bash
B=com.jessicamumby.whenIsBinApp
xcrun simctl uninstall "$UDID" $B 2>/dev/null; xcrun simctl privacy "$UDID" reset all $B
.claude/skills/verify-when-is-bin/scripts/tap_system_button.sh "$UDID" Allow 300 "$RUN_DIR" > "$RUN_DIR/tap.log" 2>&1 &
echo "pid $! tap_system_button" >> "$RUN_DIR/started.txt"; echo "app $UDID $B" >> "$RUN_DIR/started.txt"
( set -o pipefail; RUN_DIR="$RUN_DIR" flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/verify/reminders_switch_after_permission_test.dart -d "$UDID" --keep-app-running \
  --dart-define=GIT_SHA=$(git rev-parse --short HEAD) 2>&1 | tee "$RUN_DIR/drive.log" ); echo "exit=$?" >> "$RUN_DIR/drive.log"
```

Expect, in order: `permission before: allowed=false`; `after the switch: denied-snackbar` (Allow lands about 8 s after the alert, past the 5 s wait) or `reminders-on`; `permission after the alert: allowed=true`; on the late path, `late grant` then `after the second switch: reminders-on`; `pending notifications: 2` with two `title="Bins out tomorrow" body="Put out the Black bin tomorrow."` lines; `settings shows "Build <head>"`; `All tests passed`, `exit=0`. Screenshots `sw-1-reminders-off`, `sw-2-late-grant` (snackbar, switch off), `sw-3-reminders-on`, `sw-4-settings-build-stamp`. Then relaunch and read prefs (SKILL.md, Evidence): `sw-5-relaunch.png` shows `Reminders on`; `"flutter.reminders_enabled" => true`.

### Onboarding entry point (`rem-after-grant`, needs the API)

Preconditions:

- Baseline from [README](./README.md); doctor passed in this run.
- Fresh install and reset permission (`xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp`), so notification permission is undecided. The drive logs `VERIFY state permission before prompt: allowed=false`; `true` means the precondition failed.
- A postcode whose council answers quickly and returns a non-provisional schedule with upcoming dates (the drive onboards through the postcode-only path, so use the [onboarding feature's](./onboarding-postcode-only.md) postcode check; or add `--dart-define=VERIFY_ADDRESS=<part of a public building's label>` to let it pick that address when the council lists addresses, since only the schedule matters here). A provisional schedule never gets reminders by design: PRECONDITION, not a fail.
- The simulator's window visible on the current Space and Accessibility permission for the terminal (for `tap_system_button.sh`).

Not yet driven (blocked on 5 October 2026 by the API allowance and the lack of a fast postcode-only council).

- **Start the host-side Allow, then the drive.** The helper waits for the alert and taps Allow, in practice about 8 s after it appears, which is the late-Allow case this path must survive (the resume re-sync):

  ```bash
  .claude/skills/verify-when-is-bin/scripts/tap_system_button.sh "$UDID" Allow 400 "$RUN_DIR" > "$RUN_DIR/tap.log" 2>&1 &
  echo "pid $! tap_system_button" >> "$RUN_DIR/started.txt"
  ( set -o pipefail; RUN_DIR="$RUN_DIR" flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/verify/reminders_after_permission_test.dart -d "$UDID" --keep-app-running \
    --dart-define=GIT_SHA=$(git rev-parse --short HEAD) --dart-define=VERIFY_POSTCODE='<postcode>' \
    2>&1 | tee "$RUN_DIR/drive.log" ); echo "exit=$?" >> "$RUN_DIR/drive.log"
  cat "$RUN_DIR/tap.log"
  ```

  The helper's timeout must cover the build plus the lookup (400 s is safe on a warm build).
- **Onboard.** Same steps as the onboarding feature, screenshots prefixed `rem-`.
- **Turn on reminders.** `tester.tap(find.text('Turn on reminders'))`. Log `VERIFY action tapped "Turn on reminders"`, then `VERIFY state after onboarding: bin-days`. `tap.log` shows `seen "Allow" at <time>` then `TAPPED: "Allow" gone`.
- **Permission.** Log `VERIFY state permission after prompt: allowed=true` (read with `checkPermissions()`, read-only).
- **Pending reminders.** Log `VERIFY state pending notifications: <n>` with one `VERIFY pending id=... title="Bins out tomorrow" body="Put out the ... tomorrow."` per reminder, read with `pendingNotificationRequests()` (read-only). Screenshot `rem-4-bin-days` shows `Reminders on`.
- **Cross-check.** Relaunch, terminate, read prefs (SKILL.md, Evidence): `"flutter.reminders_enabled" => 1`, `"flutter.onboarded" => 1`.
- **Prompt-straight-away variant.** Not reachable with the helper's ~8 s latency; needs a person at the simulator, or Jess on the iPhone (rung 2).
- **Denied variant.** Run the helper with `"Don't Allow"`; expect `allowed=false` and the drive to fail at the permission step with its PRECONDITION message (that drive is built for the grant path; a denied drive needs its own expectation).
- **Reset.** `xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp`. Uninstall alone keeps the notification permission on the simulator (a run after uninstall only logged `allowed=true`).

States: first launch, loading (button spinner while the alert is open), after the grant (resume), denied, after relaunch (re-sync on launch). Not applicable: offline (scheduling is local), signed out (no accounts), provisional schedule (reminders deliberately off; its own state, not this feature).

## Stable selectors

- Visible copy: `Turn on reminders`, `Your bin days`, `Reminders on`, `Remind me to put the bins out`.
- iOS alert button labels, matched exactly by OCR on the host: `Allow`, `Don't Allow`.
- Plugin reads (no app code): `IOSFlutterLocalNotificationsPlugin.checkPermissions()`, `FlutterLocalNotificationsPlugin().pendingNotificationRequests()`.

## Evidence and cross-check

- Screenshots: `rem-1..3` (onboarding), `rem-4-bin-days.png` (`Reminders on`), the helper's `alert-*.png` (the iOS alert before the tap) and `alert-after-*.png` (gone).
- Drive log: the `permission ... allowed=` lines and every `pending id=` line; `exit=0`.
- Cross-check: the drive's `pending id=` lines come from iOS's own list (read-only plugin call), and the prefs plist read after a clean relaunch shows `"flutter.reminders_enabled" => 1` (`reminder_time` is absent until the user picks one; evening is the default). No host-side file holds the pending list on the iOS 26 simulator.

## Gotchas

- `simctl privacy` has no notifications service; the alert must be answered on screen. Don't edit the simulator's BulletinBoard files to fake a grant: that injects the state under test.
- Reminders exist only for collections at least a reminder-time ahead. A schedule with nothing upcoming, or a provisional one, legitimately yields zero pending: check the bin-days screen before calling it NOT VERIFIED.
- Read pending notifications by polling for a few seconds: turning the switch on also fires the app-level re-sync (cancel, then re-add), and an immediate read once returned 0 mid-sync.
- Each `tap_system_button.sh` run clicks only inside the window titled for your UDID; if another agent's Simulator window covers it, the click can land on theirs. Keep yours raised (the helper raises it) and don't run two tap helpers at once.

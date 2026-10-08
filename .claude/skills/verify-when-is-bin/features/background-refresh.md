# Schedule re-check: resume and background

A user who relies on reminders may not open the app for weeks, so the saved schedule is re-checked on three triggers: every cold launch (always), coming back to the app (only if the last check is 12 hours old or more), and a background task (Android WorkManager about once a day with a network; iOS BGAppRefreshTask whenever iOS allows). A moved collection is saved, the reminders follow it, and Settings shows `Dates last checked: <weekday d Month, HH:mm>` under the saved address.

`bg-stamp` and `bg-resume` are driven on rung 1 by `integration_test/verify/recheck_resume_test.dart` (first passed 8 October 2026 at e9b9936). The Android job and the iOS task are mapped, not yet driven. The unit and widget tests cover the logic (`test/services/schedule_recheck_service_test.dart`, `test/services/background_refresh_test.dart`, the resume group in `test/main_test.dart`). What only a device can show is that the OS actually runs the task and the plugins work in the background isolate on a release build.

## Sub-features

- `bg-stamp`: Settings shows `Dates last checked:` after any check, and nothing before the first.
- `bg-resume`: returning to the app after 12 hours or more re-checks (one conditional `GET /schedules/{token}`); within 12 hours it does not.
- `bg-android-job`: the WorkManager job runs on a release build and updates `Dates last checked`.
- `bg-ios-task`: the BGAppRefreshTask runs on a real iPhone and updates `Dates last checked`.

## How to get to it (user POV)

- Settings (the cog on "Your bin days"): the line under the saved address.
- Background the app (home gesture) and come back.
- Nothing at all for the background task: it is invisible until `Dates last checked` moves.

## Driving it

Preconditions: baseline from [README](./README.md), doctor passed, an onboarded app with a saved address, and an API allowance (every check is one API request; `scripts/find_postcode_only.sh` exit 2 means INCONCLUSIVE).

The 12-hour interval is the obstacle: a check right after onboarding is turned away. Move the clock, not the code.

- **bg-stamp (rung 1).** After onboarding, open Settings: `Dates last checked: <today>, <time of the lookup>`. Screenshot `bg-stamp.png`.
- **bg-stamp and bg-resume (rung 1, simulator).** One drive, no extra arranging:

  ```bash
  ( set -o pipefail; RUN_DIR="$RUN_DIR" flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/verify/recheck_resume_test.dart -d "$UDID" --keep-app-running \
    --dart-define=GIT_SHA=$(git rev-parse --short HEAD) 2>&1 | tee "$RUN_DIR/drive.log" ); echo "exit=$?" >> "$RUN_DIR/drive.log"
  ```

  It saves a fixture schedule against Cambridge Central Library's real token (`p:8ccd92739644bc77`), a public building the API answers with `404 no_schedule`. The app counts that as a completed check, so `schedule_checked_at` moves only when the API really answered. The drive starts the stamp two days old, waits for the launch check to move it, sets it 13 hours old, backgrounds and returns (`handleAppLifecycleStateChanged`), expects a fresh stamp, then returns again at once and expects no change. It costs two API requests. Expect `VERIFY state resume after 13h: schedule_checked_at=<now>` and `resume within 12h: ... (unchanged=true)`, then Settings `Dates last checked: <today, time>` and `Build <sha>`. The bin-days screenshot also shows the collection after next, the reminder caveat and the iOS calendar card. For a read-back outside the test binding, terminate the app, `plutil -p` the prefs plist, cold-launch with `xcrun simctl launch`, terminate again, and check that `flutter.schedule_checked_at` moved. Use `plutil -p`, not `-extract`: the dot in `flutter.` reads as a key path.
- **bg-android-job (emulator `Medium_Phone_API_36.1`, release).**
  1. `flutter build apk --release --dart-define=GIT_SHA=$(git rev-parse --short HEAD) && adb install -r build/app/outputs/flutter-apk/app-release.apk`. Onboard by hand. Settings: `Build <sha>`, note the `Dates last checked` time.
  2. Move the emulator clock forward 13 hours: Settings app, System, Date & time, turn off automatic time, set the time by hand. (No root needed.)
  3. Find the job: `adb shell dumpsys jobscheduler | grep -B2 -A6 'com.jessicamumby.when_is_bin_app/androidx.work.impl.background.systemjob.SystemJobService'`; the `JOB #u0aNNN/<id>` line gives the id.
  4. Force it (ignores its delay and network constraint): `adb shell cmd jobscheduler run -f com.jessicamumby.when_is_bin_app <id>`.
  5. Proof it ran: `adb logcat -d | grep -E 'WM-WorkerWrapper.*BackgroundWorker'` shows `Worker result SUCCESS`. Then open the app: `Dates last checked` reads the moved clock's time. Screenshot `bg-android-job.png`.
  6. Restore automatic time.
  Stored value: a release APK refuses `run-as`, so the Settings line is the read-back. On a debug APK, `adb shell run-as com.jessicamumby.when_is_bin_app cat shared_prefs/FlutterSharedPreferences.xml | grep schedule_checked_at` reads it directly.
- **bg-ios-task (rung 2, Jess's iPhone, only with her consent).** BGTaskScheduler does not run on the iOS Simulator at all. On the phone it needs Xcode attached, so this is a debug or profile build, not the store build:
  1. Open `ios/Runner.xcworkspace`, run the Runner scheme on the iPhone, onboard, and note `Dates last checked`.
  2. Background the app. In Xcode, Debug, Pause, then at `(lldb)`: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jessicamumby.whenIsBinApp.scheduleRefresh"]`, then Continue.
  3. The console logs the workmanager task start and finish. The 12-hour interval still applies, so the stamp only moves if the last check was 12 hours ago or more. Otherwise the run is correct but proves only that the task launched.
  4. Stored value: `xcrun devicectl device copy from ... --source Library/Preferences/com.jessicamumby.whenIsBinApp.plist` (see SKILL.md) and `plutil -p` for `flutter.schedule_checked_at`.
  A release build cannot be forced; on the store build, iOS runs the task when it chooses (usually overnight on charge for an app used daily, rarely for one never opened). Do not report `bg-ios-task` VERIFIED from a release build: say "launch path proven on debug; release cadence is iOS's".

## Stable selectors

- Visible copy: `Dates last checked: ` (prefix; the rest is the device's local time), `Remove saved address`, `Build `.

## Evidence and cross-check

- Screenshots: `bg-stamp.png`, `bg-resume.png`, `bg-android-job.png`.
- Cross-check: `flutter.schedule_checked_at` (an ISO 8601 UTC string) from the prefs plist (iOS) or `FlutterSharedPreferences.xml` (Android debug), which must match the Settings line in local time.

## Gotchas

- In a drive, never pump between lifecycle states. While the app is hidden or paused the binding schedules no frames, so a `pump()` there never returns and the drive hangs until killed. Send the whole sequence, then pump once after `resumed`.

- Every check is an API request against the per-IP allowance; a rate-limited check fails silently and leaves `Dates last checked` unchanged, by design. That is INCONCLUSIVE, not a pass.
- `Dates last checked` moves on a 304 too: it records that the app asked, not that anything changed.
- While the app is running, the background task hands its work to the app's own isolate, so a forced Android job with the app in the foreground still updates the stamp, through the app.

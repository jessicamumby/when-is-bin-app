# Postcode-only onboarding

On first launch a user types their postcode. When the council needs nothing beyond it (the API answers `required_input: none`, or `property_id` with an empty candidate list), onboarding opens the same "A few more details" form the home screen uses, with no fields, just the council name, the postcode and "Find my bin day". The lookup runs, onboarding moves to the reminder step, and "Turn on reminders" finishes onboarding on "Your bin days". It used to dead-end on "This council needs more information. Please try again later." (fixed in PR #30).

## Sub-features

- `onb-postcode-only-form` the postcode leads to the field-less address form, not a dead end and not the address picker.
- `onb-postcode-only-lookup` "Find my bin day" on that form finds the schedule and returns to the reminder step.
- `onb-postcode-only-finish` "Turn on reminders" lands on "Your bin days" with a next collection, whatever the permission alert does.
- `onb-postcode-only-relaunch` after the app is killed and reopened it opens on "Your bin days", not onboarding.

## How to get to it (user POV)

- First launch only: the "Find your bin day" screen with a `Postcode` field and `Find my bin day`.
- The same address form is reachable from the home search screen (after removing the saved address), but that is a different entry point: it ends on "Your bin days" directly, with no reminder step. Do not report it as this feature.

## Driving it with flutter drive

Preconditions:

- Baseline from [README](./README.md); `scripts/doctor.sh "$UDID"` passed in this run.
- First launch: `xcrun simctl uninstall "$UDID" com.jessicamumby.whenIsBinApp; xcrun simctl privacy "$UDID" reset all com.jessicamumby.whenIsBinApp` (simulator you own only). The drive fails with `PRECONDITION: onboarding is not showing` otherwise.
- API allowance left: this drive costs one `GET /addresses`, one `POST /lookups` and up to two minutes of long-poll waits. If the day's anonymous allowance is spent (any `429` with a `Retry-After` in hours), the feature is unreachable today: INCONCLUSIVE, not a fail.
- A postcode that is postcode-only today with a council that answers quickly. Check before driving (costs one anonymous request per postcode):

  ```bash
  .claude/skills/verify-when-is-bin/scripts/find_postcode_only.sh "ZE1 0AA" "<other candidates>"
  ```

  Use a `POSTCODE-ONLY` line, preferring a low `expected_wait` and `success_rate` near 1 and no `notice=council_site_unavailable`. Known answers, 5 October 2026: `ZE1 0AA` (Shetland Islands Council) was the only `required_input=none` found, with its council site failing (`expected_wait=615s`, `success_rate=0.29`); `CB4 2HX` (Cambridge, the postcode in the fix and its unit test) now lists addresses, so it no longer exercises this path. Not postcode-only that day (don't re-probe): Brighton BN1 1JE, Exeter EX1 1JN, Norwich NR2 1NH, Somerset TA1 1HE, Colchester CO1 1JB, Peterborough PE1 1HQ, Lincoln LN1 1DD, York YO1 9QN, Dundee DD1 3BY, Fife KY1 1XT, Scottish Borders TD6 0SA, Moray IV30 1BX, Orkney KW15 1NX, Western Isles HS1 2BW, Isles of Scilly TR21 0LW, Highland IV1 1AA, Perth PH1 5PH, Powys LD1 5LG, Aberdeen AB10 1AB, Argyll PA34 4AW, Aberdeenshire AB51 3WA, Angus DD8 3LG, Clackmannanshire FK10 1EB, North Ayrshire KA12 8EE, Dumfries DG1 2DD, Inverclyde PA15 1LY, Anglesey LL77 7TW, Ceredigion SY23 2DE, Cornwall TR1 2EB, Herefordshire HR1 2PJ, Pembrokeshire SA61 1TP. Rutland LE15 6HP is unsupported; Carlisle CA1 1RQ is outside coverage.

- **Enter postcode.** `tester.enterText(inOnboarding(find.widgetWithText(TextField, 'Postcode')), postcode)` then `tester.tap(inOnboarding(find.text('Find my bin day')))`. Log: `VERIFY state after postcode: address-form`; screenshot `onb-1-postcode-entered`. `address-picker` means the postcode is not postcode-only (PRECONDITION); `dead-end` is the old bug (BEHAVIOUR).
- **Field-less form.** Log: `VERIFY state address form shows 0 text fields (0 = postcode only)`; screenshot `onb-2-address-form` shows "A few more details", `<Council> • <postcode>` and one button.
- **Find bin day.** `tester.tap(inAddressForm(find.text('Find my bin day')))`. Within 150 s: `VERIFY state after lookup: reminder-step`; screenshot `onb-3-reminder-step` ("Get bin day reminders", the two times, "Turn on reminders"). `VERIFY state after lookup: timeout` with `onb-x-after-lookup.png` showing the idle form means the council outlasted the app's two-minute wait (see Gotchas).
- **Finish.** `tester.tap(find.text('Turn on reminders'))`. `VERIFY state after onboarding: bin-days`, `Next collection` present; screenshot `onb-4-bin-days`. The iOS permission alert may sit on top in the host's view; onboarding must not wait on it.
- All of the above in one command:

  ```bash
  ( set -o pipefail; RUN_DIR="$RUN_DIR" flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/verify/onboarding_postcode_only_test.dart -d "$UDID" --keep-app-running \
    --dart-define=GIT_SHA=$(git rev-parse --short HEAD) --dart-define=VERIFY_POSTCODE='<postcode>' \
    2>&1 | tee "$RUN_DIR/drive.log" ); echo "exit=$?" >> "$RUN_DIR/drive.log"
  ```

- **Relaunch.** After the drive exits: `xcrun simctl launch --terminate-running-process "$UDID" com.jessicamumby.whenIsBinApp`, wait about 8 s, `xcrun simctl io "$UDID" screenshot "$RUN_DIR/onb-5-relaunch.png"`. "Your bin days" with the postcode under it, not "Find your bin day". Then terminate and read prefs (SKILL.md, Evidence).
- **Reset.** As in Preconditions (uninstall plus `privacy reset all`).

States: first launch, loading (button spinner, then the form's spinner), error (the red card with "Try another postcode"; rate limited or offline copy), after relaunch. Not applicable: signed out (no accounts), selected/expanded (no list on this path), disabled (the form has no fields to validate).

## Stable selectors

- Visible copy: `Find your bin day`, `Postcode` (field label), `Find my bin day` (scoped: onboarding and the form both have one), `A few more details`, `Select your address` (the picker: wrong path), `This council needs more information` (the old dead end), `Try another postcode` (lookup error card), `When should we remind you?`, `Turn on reminders`, `Your bin days`, `Next collection`.
- Screen types used only for scoping: `OnboardingScreen`, `AddressEntryScreen`. Proposed product change: Keys such as `ValueKey('onboarding.postcode')`, `ValueKey('address.submit')`.

## Evidence and cross-check

- Screenshots: `onb-1-postcode-entered.png`, `onb-2-address-form.png` (field-less form, council and postcode visible), `onb-3-reminder-step.png`, `onb-4-bin-days.png`, `onb-5-relaunch.png` (host capture after relaunch). DEBUG banner visible on all.
- Drive log: the `VERIFY` lines and `exit=0`.
- Cross-check (read-only, app stopped): prefs plist shows `"flutter.onboarded" => 1`, `"flutter.saved_postcode" => "<postcode>"`, `"flutter.saved_address" => "<postcode>"` (a postcode-only address is saved as the postcode), `"flutter.reminders_enabled" => 1`. Command in SKILL.md, Evidence.

## Gotchas

- A slow council is not a pass or a fail of this feature: the app waits two minutes, then the form goes quiet with no message (the lookup may still finish server-side). That is INCONCLUSIVE for this feature, and worth reporting to Jess as a product gap. A second attempt a few minutes later often returns the server's finished lookup quickly.
- Each attempt costs `GET /addresses`, `POST /lookups` and a run of long-poll waits from the same IP as your probes. After a `429` with a long `Retry-After`, stop: retrying extends nothing but your wait.
- Do not tap the unscoped `find.text('Find my bin day')` on the form: onboarding's own button is still mounted underneath, and the tap lands on nothing (the first harness run did exactly that and sat on the form for 150 s).
- Proven so far (5 October 2026, ZE1 0AA, debug, iPhone 17 Pro simulator, head 9e40ab8): `onb-postcode-only-form` (field-less form, no dead end). `-lookup`, `-finish` and `-relaunch` not yet reached: Shetland's lookup never finished inside the app's wait, then the day's API allowance ran out.
- The permission alert left on screen by this drive is not part of this feature; the reminders feature answers it.

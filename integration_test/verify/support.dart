import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:when_is_bin_app/screens/address_entry_screen.dart';
import 'package:when_is_bin_app/screens/address_select_screen.dart';
import 'package:when_is_bin_app/screens/onboarding_screen.dart';

/// Shared helpers for the verify-when-is-bin drives. Verification scaffolding
/// only: nothing here is imported by the app.

/// The postcode the onboarding drives use. Override with
/// `--dart-define=VERIFY_POSTCODE=...`. The default must belong to a council
/// whose `/addresses` answer has no candidate list (postcode-only).
const verifyPostcode = String.fromEnvironment(
  'VERIFY_POSTCODE',
  defaultValue: 'ZE1 0AA',
);

/// Part of an address-picker label to choose when the council lists
/// addresses. Empty (the default) means the drive insists on the postcode-only
/// path and treats a picker as a failed precondition. Drives that only need a
/// schedule (the reminders feature) may set it with
/// `--dart-define=VERIFY_ADDRESS=...`; use a public building, never a home.
const verifyAddress = String.fromEnvironment('VERIFY_ADDRESS');

/// [matching] inside the address form only. Onboarding stays mounted under
/// the form and has its own "Find my bin day" button and postcode field, so an
/// unscoped finder can hit the covered screen instead.
Finder inAddressForm(Finder matching) =>
    find.descendant(of: find.byType(AddressEntryScreen), matching: matching);

/// [matching] inside the onboarding screen only.
Finder inOnboarding(Finder matching) =>
    find.descendant(of: find.byType(OnboardingScreen), matching: matching);

/// Prints one greppable line to the drive log.
void mark(String message) {
  // ignore: avoid_print
  print('VERIFY $message');
}

/// Pumps until [finder] matches, or fails with [reason] after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 400));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(reason ?? 'Timed out after $timeout waiting for $finder');
}

/// Pumps until one of [outcomes] matches and returns its name, or null on
/// timeout. Lets a drive tell the expected screen apart from a dead end.
Future<String?> pumpUntilAny(
  WidgetTester tester,
  Map<String, Finder> outcomes, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 400));
    for (final entry in outcomes.entries) {
      if (entry.value.evaluate().isNotEmpty) return entry.key;
    }
  }
  return null;
}

/// Captures the Flutter surface as `<RUN_DIR>/<name>.png` via the driver.
///
/// OS overlays (the notification permission alert) are not part of the
/// Flutter surface; capture those from the host with `xcrun simctl io`.
Future<void> shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pump();
  await binding.takeScreenshot(name);
  mark('screenshot $name');
}

/// Drives first-launch onboarding with [verifyPostcode] up to the reminder
/// step, through the address form a postcode-only council gets. Screenshots
/// are prefixed with [prefix]. Fails with a PRECONDITION or BEHAVIOUR reason
/// the verdict can quote.
Future<void> driveOnboardingToReminderStep(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String prefix,
}) async {
  await pumpUntil(
    tester,
    find.text('Find your bin day'),
    reason: 'PRECONDITION: onboarding is not showing, so this is not a first '
        'launch. Uninstall the app from the simulator and drive again.',
  );
  mark('state first-launch onboarding visible');

  await tester.enterText(
    inOnboarding(find.widgetWithText(TextField, 'Postcode')),
    verifyPostcode,
  );
  await shot(binding, tester, '$prefix-1-postcode-entered');
  await tester.tap(inOnboarding(find.text('Find my bin day')));
  mark('action tapped "Find my bin day" with postcode $verifyPostcode');

  final afterPostcode = await pumpUntilAny(tester, {
    'address-form': find.text('A few more details'),
    'address-picker': find.text('Select your address'),
    'dead-end': find.textContaining('This council needs more information'),
  });
  mark('state after postcode: ${afterPostcode ?? 'timeout'}');
  if (afterPostcode != 'address-form') {
    await shot(binding, tester, '$prefix-x-after-postcode');
  }
  if (afterPostcode == 'address-picker' && verifyAddress.isNotEmpty) {
    await _pickAddress(binding, tester, prefix: prefix);
    return;
  }
  switch (afterPostcode) {
    case 'address-form':
      break;
    case 'address-picker':
      fail('PRECONDITION: $verifyPostcode offers an address list, so it is not '
          'a postcode-only council today. Pick another postcode (see the '
          'feature file) and drive again.');
    case 'dead-end':
      fail('BEHAVIOUR: onboarding dead-ended on "This council needs more '
          'information" for $verifyPostcode.');
    default:
      fail('Timed out after the postcode: no address form, picker or dead end '
          '(offline, rate-limited or API down?). See the screenshot.');
  }

  final fieldCount = inAddressForm(find.byType(TextField)).evaluate().length;
  mark('state address form shows $fieldCount text fields (0 = postcode only)');
  await shot(binding, tester, '$prefix-2-address-form');
  await tester.tap(inAddressForm(find.text('Find my bin day')));
  mark('action tapped "Find my bin day" on the address form');

  await _awaitReminderStep(binding, tester, prefix: prefix);
}

/// Picks the [verifyAddress] candidate on the address picker.
Future<void> _pickAddress(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String prefix,
}) async {
  final candidate = find.descendant(
    of: find.byType(AddressSelectScreen),
    matching: find.textContaining(verifyAddress),
  );
  await shot(binding, tester, '$prefix-2-address-picker');
  expect(
    candidate,
    findsOneWidget,
    reason: 'PRECONDITION: the picker has no single address containing '
        '"$verifyAddress".',
  );
  await tester.tap(candidate);
  mark('action picked the address containing "$verifyAddress"');
  await _awaitReminderStep(binding, tester, prefix: prefix);
}

Future<void> _awaitReminderStep(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required String prefix,
}) async {
  final afterLookup = await pumpUntilAny(
    tester,
    {
      'reminder-step': find.text('When should we remind you?'),
      'lookup-error': find.text('Try another postcode'),
    },
    // Real council lookups can take tens of seconds.
    timeout: const Duration(seconds: 150),
  );
  mark('state after lookup: ${afterLookup ?? 'timeout'}');
  if (afterLookup != 'reminder-step') {
    await shot(binding, tester, '$prefix-x-after-lookup');
    fail('Lookup for $verifyPostcode did not reach the reminder step '
        '(${afterLookup ?? 'timeout'}). See the screenshot.');
  }
  await shot(binding, tester, '$prefix-3-reminder-step');
}

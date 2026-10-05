import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:when_is_bin_app/main.dart' as app;

import 'support.dart';

/// verify-when-is-bin feature `onb-postcode-only`.
///
/// Drives the real app against the live WhenIsBins API: a postcode whose
/// council needs no address selection completes onboarding and lands on the
/// bin days. Run by the skill with `flutter drive`, never by `flutter test`
/// in CI (it needs a device and the network).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onb-postcode-only: a postcode-only council completes '
      'onboarding and lands on the bin days', (tester) async {
    app.main();

    await driveOnboardingToReminderStep(binding, tester, prefix: 'onb');

    await tester.tap(find.text('Turn on reminders'));
    mark('action tapped "Turn on reminders"');

    // The notification permission alert may sit on top; onboarding must not
    // wait on it (the request is bounded), so the bin days appear regardless.
    final landed = await pumpUntilAny(tester, {
      'bin-days': find.text('Your bin days'),
    });
    mark('state after onboarding: ${landed ?? 'timeout'}');
    await shot(binding, tester, 'onb-4-bin-days');
    expect(
      landed,
      'bin-days',
      reason: 'BEHAVIOUR: onboarding did not hand over to "Your bin days".',
    );
    expect(find.text('Turn on reminders'), findsNothing);
    expect(find.text('A few more details'), findsNothing);
    expect(find.text('Next collection'), findsOneWidget);
    mark('state bin days shown for $verifyPostcode with a next collection');
  });
}

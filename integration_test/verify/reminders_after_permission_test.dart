import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:when_is_bin_app/main.dart' as app;

import 'support.dart';

/// verify-when-is-bin feature `rem-after-grant`.
///
/// Onboards with a fresh install, taps "Turn on reminders", and lets the host
/// tap "Allow" on the iOS permission alert (scripts/tap_system_button.sh, run
/// alongside this drive). Then reads, without changing anything, what iOS
/// actually holds: the permission and the pending local notifications.
///
/// iOS drops notifications scheduled before permission is granted, so when
/// the host taps Allow after the app's 5 second permission wait has expired,
/// only the app's re-sync on resume can put the reminders back. A non-empty
/// pending list after a late Allow is the discriminating evidence.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rem-after-grant: reminders are pending after the user allows '
      'notifications', (tester) async {
    app.main();
    final ios = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    expect(ios, isNotNull, reason: 'PRECONDITION: iOS only.');

    Future<bool> allowed() async =>
        (await ios!.checkPermissions())?.isEnabled ?? false;

    await driveOnboardingToReminderStep(binding, tester, prefix: 'rem');
    mark('state permission before prompt: allowed=${await allowed()}');

    await tester.tap(find.text('Turn on reminders'));
    mark('action tapped "Turn on reminders"; waiting for the host to tap '
        'Allow on the iOS alert');

    final landed = await pumpUntilAny(tester, {
      'bin-days': find.text('Your bin days'),
    });
    mark('state after onboarding: ${landed ?? 'timeout'}');
    expect(landed, 'bin-days');

    // Read-only: poll the OS permission while the host answers the alert.
    final grantDeadline = DateTime.now().add(const Duration(seconds: 120));
    var granted = false;
    while (DateTime.now().isBefore(grantDeadline)) {
      await tester.pump(const Duration(seconds: 1));
      granted = await allowed();
      if (granted) break;
    }
    mark('state permission after prompt: allowed=$granted');
    expect(
      granted,
      isTrue,
      reason: 'PRECONDITION: notifications were never allowed. Did '
          'tap_system_button.sh run alongside the drive?',
    );

    // Give the resume re-sync a moment, then read what iOS holds.
    final pendingDeadline = DateTime.now().add(const Duration(seconds: 20));
    var pending = <PendingNotificationRequest>[];
    while (DateTime.now().isBefore(pendingDeadline)) {
      await tester.pump(const Duration(seconds: 1));
      pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      if (pending.isNotEmpty) break;
    }
    mark('state pending notifications: ${pending.length}');
    for (final request in pending) {
      mark('pending id=${request.id} title="${request.title}" '
          'body="${request.body}"');
    }

    await tester.pump(const Duration(seconds: 1));
    await shot(binding, tester, 'rem-4-bin-days');
    expect(find.text('Reminders on'), findsOneWidget);
    expect(
      pending,
      isNotEmpty,
      reason: 'BEHAVIOUR: notifications are allowed and reminders are on, '
          'but iOS holds no pending reminder.',
    );
  });
}

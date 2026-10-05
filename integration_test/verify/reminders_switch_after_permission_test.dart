import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/main.dart' as app;
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';

import 'support.dart';

/// verify-when-is-bin feature `rem-switch-after-grant`.
///
/// Needs no API: the precondition (an onboarded user with a saved schedule and
/// reminders off) is ARRANGED by writing a fixture through the app's own
/// SettingsProvider before the app starts, on a fresh install. The behaviour
/// under test comes from real interaction: the user turns the reminder switch
/// on, the host taps Allow on the iOS alert (scripts/tap_system_button.sh),
/// and iOS is then asked, read-only, what it holds.
///
/// Entry point covered: the switch on "Your bin days". Not the onboarding
/// "Turn on reminders" button (that is reminders_after_permission_test.dart).
const _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rem-switch-after-grant: turning reminders on and allowing '
      'notifications leaves reminders pending', (tester) async {
    // Arrange: two upcoming collections for a fixture property (no real
    // address), onboarded, reminders off.
    final prefs = await SharedPreferences.getInstance();
    final fixture = SettingsProvider(prefs);
    final fmt = DateFormat('yyyy-MM-dd');
    final dates = [
      fmt.format(DateTime.now().add(const Duration(days: 7))),
      fmt.format(DateTime.now().add(const Duration(days: 14))),
    ];
    final schedule = Schedule(
      propertyId: 'p:verify-fixture',
      addressMatch: 'exact',
      collections: [
        Collection(name: 'Black bin', wasteType: 'rubbish', dates: dates),
      ],
      byDate: [
        for (final date in dates)
          ByDateEntry(
            date: date,
            weekday: DateFormat('EEEE').format(DateTime.parse(date)),
            collections: const [
              ByDateCollection(name: 'Black bin', wasteType: 'rubbish'),
            ],
          ),
      ],
    );
    await fixture.saveAddress(
      address: 'Verify fixture (not a real address)',
      postcode: 'ZZ99 9ZZ',
      propertyId: schedule.propertyId,
    );
    await fixture.saveSchedule(schedule);
    await fixture.setRemindersEnabled(false);
    await fixture.markOnboarded();
    mark('arrange fixture schedule with collections on ${dates.join(', ')}, '
        'reminders off, onboarded');

    final ios = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    expect(ios, isNotNull, reason: 'PRECONDITION: iOS only.');
    Future<bool> allowed() async =>
        (await ios!.checkPermissions())?.isEnabled ?? false;

    app.main();
    await pumpUntil(
      tester,
      find.text('Reminders off'),
      reason: 'PRECONDITION: the app did not open on the bin days with '
          'reminders off. Uninstall it and drive again.',
    );
    mark('state bin days shown, reminders off');
    mark('state permission before: allowed=${await allowed()}');
    await shot(binding, tester, 'sw-1-reminders-off');

    await tester.tap(find.byType(Switch));
    mark('action turned the reminder switch on; waiting for the host to '
        'answer the iOS alert');

    var outcome = await pumpUntilAny(
      tester,
      {
        'reminders-on': find.text('Reminders on'),
        'denied-snackbar': find.textContaining('Turn on notifications'),
      },
      timeout: const Duration(seconds: 120),
    );
    mark('state after the switch: ${outcome ?? 'timeout'}');

    // The app waits 5 s for the verdict. If the Allow tap landed after that,
    // the switch reports "Turn on notifications ..." and stays off even though
    // the user allowed. Record it, wait for the grant, and retry the switch as
    // that user would.
    var granted = await allowed();
    final grantDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (!granted && DateTime.now().isBefore(grantDeadline)) {
      await tester.pump(const Duration(seconds: 1));
      granted = await allowed();
    }
    mark('state permission after the alert: allowed=$granted');
    expect(
      granted,
      isTrue,
      reason: 'PRECONDITION: notifications were never allowed. Did '
          'tap_system_button.sh run alongside the drive?',
    );
    if (outcome != 'reminders-on') {
      mark('state late grant: Allow arrived after the app stopped waiting; '
          'the switch stayed off');
      await shot(binding, tester, 'sw-2-late-grant');
      await pumpUntil(
        tester,
        find.text('Reminders off'),
        timeout: const Duration(seconds: 10),
      );
      // Let the snackbar clear so the switch is reachable.
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byType(Switch));
      mark('action turned the reminder switch on again, now allowed');
      outcome = await pumpUntilAny(tester, {
        'reminders-on': find.text('Reminders on'),
        'denied-snackbar': find.textContaining('Turn on notifications'),
      });
      mark('state after the second switch: ${outcome ?? 'timeout'}');
    }

    // The settings change also triggers the app-level re-sync (cancel, then
    // re-add), so poll briefly rather than reading mid-sync.
    var pending = <PendingNotificationRequest>[];
    final pendingDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(pendingDeadline)) {
      await tester.pump(const Duration(seconds: 1));
      pending =
          await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
      if (pending.length >= dates.length) break;
    }
    mark('state pending notifications: ${pending.length}');
    for (final request in pending) {
      mark('pending id=${request.id} title="${request.title}" '
          'body="${request.body}"');
    }
    await shot(binding, tester, 'sw-3-reminders-on');

    // Build identity: Settings ends with "Build <sha>".
    await tester.tap(find.text('Change reminder time'));
    await pumpUntil(tester, find.text('Reminder time'));
    final stamp = find.textContaining('Build ');
    await tester.dragUntilVisible(
      stamp,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
    mark('state settings shows "${tester.widget<Text>(stamp).data}" '
        '(drive built with GIT_SHA=$_gitSha)');
    await shot(binding, tester, 'sw-4-settings-build-stamp');
    await tester.pageBack();
    await pumpUntil(tester, find.text('Reminders on'));

    expect(
      outcome,
      'reminders-on',
      reason: 'BEHAVIOUR: the switch did not end on "Reminders on" '
          '(${outcome ?? 'timeout'}).',
    );
    expect(
      pending,
      hasLength(dates.length),
      reason: 'BEHAVIOUR: expected one pending reminder per upcoming '
          'collection date.',
    );
  });
}

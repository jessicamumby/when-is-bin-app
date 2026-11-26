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

/// verify-when-is-bin feature `set-time-late`.
///
/// Needs no API: an onboarded user with a saved schedule and reminders off is
/// ARRANGED through the app's own SettingsProvider before the app starts, as
/// in reminders_switch_after_permission_test.dart. The behaviour comes from
/// real interaction: the user opens Settings from the reminder card, picks
/// "Late evening before (10:00pm)", goes back, and turns reminders on (the
/// host taps Allow on the iOS alert with scripts/tap_system_button.sh).
///
/// iOS does not hand back a pending request's fire time, so this drive proves
/// the choice is offered, stored and shown, and that reminders are still
/// scheduled with it. The 22:00 fire time itself is pinned by the unit tests
/// in test/services/reminder_scheduler_test.dart.
const _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
const _lateEvening = 'Late evening before (10:00pm)';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('set-time-late: a user can move reminders to 10:00pm the day '
      'before', (tester) async {
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
        'reminders off, onboarded, reminder time '
        '${prefs.getString('reminder_time') ?? 'unset (evening default)'}');

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
    mark('state bin days shown; card says 7:00pm='
        '${find.textContaining('7:00pm on the day before').evaluate().isNotEmpty}');
    await shot(binding, tester, 'late-1-bin-days-default');

    await tester.ensureVisible(find.text('Change reminder time'));
    await tester.tap(find.text('Change reminder time'));
    await pumpUntil(tester, find.text('Reminder time'));
    final options = [
      'Morning before (9:00am)',
      'Evening before (7:00pm)',
      _lateEvening,
    ];
    mark('state settings options: ${[
      for (final o in options) '$o=${find.text(o).evaluate().length}',
    ].join('; ')}');
    for (final option in options) {
      expect(find.text(option), findsOneWidget,
          reason: 'BEHAVIOUR: Settings does not offer "$option".');
    }
    await shot(binding, tester, 'late-2-settings-three-options');

    await tester.tap(find.text(_lateEvening));
    await tester.pump(const Duration(seconds: 1));
    final chosen = tester
        .widget<RadioGroup<Object?>>(
          find.byWidgetPredicate((w) => w is RadioGroup),
        )
        .groupValue;
    mark('action tapped "$_lateEvening"; selected=$chosen; stored '
        'reminder_time=${prefs.getString('reminder_time')}');
    expect(prefs.getString('reminder_time'), 'lateEvening',
        reason: 'BEHAVIOUR: the late evening choice was not stored.');
    await shot(binding, tester, 'late-3-settings-late-evening-selected');

    final stamp = find.textContaining('Build ');
    await tester.dragUntilVisible(
      stamp,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
    mark('state settings shows "${tester.widget<Text>(stamp).data}" '
        '(drive built with GIT_SHA=$_gitSha)');
    await shot(binding, tester, 'late-4-settings-build-stamp');

    await tester.pageBack();
    await pumpUntil(tester, find.text('Reminders off'));
    final card = find.textContaining('10:00pm on the day before');
    mark('state back on bin days; card says 10:00pm='
        '${card.evaluate().isNotEmpty}');
    expect(card, findsOneWidget,
        reason: 'BEHAVIOUR: the reminder card does not name 10:00pm.');
    await shot(binding, tester, 'late-5-bin-days-10pm');

    await tester.ensureVisible(find.byType(Switch));
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
      // The Allow tap landed after the app's 5 s wait; retry as a user would.
      await pumpUntil(
        tester,
        find.text('Reminders off'),
        timeout: const Duration(seconds: 10),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byType(Switch));
      mark('action turned the reminder switch on again, now allowed');
      outcome = await pumpUntilAny(tester, {
        'reminders-on': find.text('Reminders on'),
        'denied-snackbar': find.textContaining('Turn on notifications'),
      });
      mark('state after the second switch: ${outcome ?? 'timeout'}');
    }

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
    await shot(binding, tester, 'late-6-reminders-on-10pm');

    expect(outcome, 'reminders-on',
        reason: 'BEHAVIOUR: the switch did not end on "Reminders on" '
            '(${outcome ?? 'timeout'}).');
    expect(pending, hasLength(dates.length),
        reason: 'BEHAVIOUR: expected one pending reminder per upcoming '
            'collection date with the late evening time chosen.');
  });
}

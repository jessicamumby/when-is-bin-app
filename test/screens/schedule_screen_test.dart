import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/schedule_screen.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';

import '../fakes/fake_api.dart';
import '../fakes/fake_notification_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A collection three days out, so there is always something to remind about.
  final nextCollection = DateTime.now().add(const Duration(days: 3));
  final nextCollectionIso = DateFormat('yyyy-MM-dd').format(nextCollection);

  Schedule schedule() {
    return Schedule(
      propertyId: 'p:4c5ee6c2f2c7c959',
      addressMatch: 'exact',
      collections: [
        Collection(
          name: 'Black bin',
          wasteType: 'refuse',
          dates: [nextCollectionIso],
        ),
      ],
      byDate: [
        ByDateEntry(
          date: nextCollectionIso,
          weekday: DateFormat('EEEE').format(nextCollection),
          collections: const [
            ByDateCollection(name: 'Black bin', wasteType: 'refuse'),
          ],
        ),
      ],
    );
  }

  Future<SettingsProvider> makeSettings({bool remindersEnabled = false}) async {
    SharedPreferences.setMockInitialValues({
      'reminders_enabled': remindersEnabled,
    });
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  Widget buildApp(SettingsProvider settings, ReminderSyncService sync) {
    final lookup = LookupProvider(api: FakeWhenIsBinsApi())
      ..restoreSchedule(schedule());
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
        Provider<ReminderSyncService>.value(value: sync),
      ],
      child: const MaterialApp(home: ScheduleScreen()),
    );
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('the switch shows the persisted reminder setting',
      (tester) async {
    final settings = await makeSettings(remindersEnabled: true);

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(
          notifications: FakeNotificationScheduler(),
          now: DateTime.now,
        ),
      ),
    );

    expect(switchValue(tester), isTrue);
    expect(find.text('Reminders on'), findsOneWidget);
  });

  testWidgets('turning reminders on schedules them and persists the switch',
      (tester) async {
    final settings = await makeSettings();
    final scheduler = FakeNotificationScheduler();

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );
    expect(switchValue(tester), isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isTrue);
    expect(settings.remindersEnabled, isTrue);
    expect(scheduler.scheduled, hasLength(1));
    expect(scheduler.scheduled.single.single.binNames, ['Black bin']);
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('keeps reminders off and warns when permission is denied',
      (tester) async {
    final settings = await makeSettings();
    final scheduler = FakeNotificationScheduler()..permissionGranted = false;

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
    expect(settings.remindersEnabled, isFalse);
    expect(scheduler.scheduled, isEmpty);
    expect(
      find.text(
        'Turn on notifications for this app in your device settings to get '
        'bin reminders.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('turning reminders off cancels them and persists the switch',
      (tester) async {
    final settings = await makeSettings(remindersEnabled: true);
    final scheduler = FakeNotificationScheduler();

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
    expect(settings.remindersEnabled, isFalse);
    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.permissionRequests, 0);
  });
}

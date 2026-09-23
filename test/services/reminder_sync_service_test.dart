import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';

import '../fakes/fake_notification_scheduler.dart';

Schedule scheduleWith(List<Collection> collections) {
  return Schedule(
    propertyId: 'p:4c5ee6c2f2c7c959',
    addressMatch: 'exact',
    collections: collections,
  );
}

Collection collection(
  String name,
  List<String> dates, {
  bool subscriptionRequired = false,
}) {
  return Collection(
    name: name,
    wasteType: 'refuse',
    dates: dates,
    subscriptionRequired: subscriptionRequired,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 1);

  group('ReminderSyncService.sync', () {
    test('schedules reminders for the saved schedule when enabled', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: scheduleWith([
          collection('Black bin', ['2026-09-10', '2026-09-24']),
        ]),
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(2));
      expect(reminders.first.fireAt, DateTime(2026, 9, 9, 19, 0));
      expect(scheduler.scheduled, hasLength(1));
      expect(scheduler.scheduled.single, hasLength(2));
      expect(scheduler.scheduled.single.first.binNames, ['Black bin']);
      expect(scheduler.cancelAllCalls, 0);
    });

    test('cancels everything and schedules nothing when disabled', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: scheduleWith([collection('Black bin', ['2026-09-10'])]),
        enabled: false,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });

    test('cancels everything when no schedule is saved', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: null,
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });

    test('re-syncs from the current time, dropping reminders that have fired',
        () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        // A week after the first collection, so only the second is upcoming.
        now: () => DateTime(2026, 9, 15),
        notifications: scheduler,
      );

      final reminders = await sync.sync(
        schedule: scheduleWith([
          collection('Black bin', ['2026-09-10', '2026-09-24']),
        ]),
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(1));
      expect(reminders.single.collectionDate, DateTime(2026, 9, 24));
    });
  });

  group('ReminderSyncService exclusions', () {
    test('schedules nothing for a provisional schedule', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: Schedule(
          propertyId: 'p:4c5ee6c2f2c7c959',
          addressMatch: 'exact',
          provisional: true,
          collections: [collection('Black bin', ['2026-09-10'])],
        ),
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });

    test('skips collections that need a subscription', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: scheduleWith([
          collection('Black bin', ['2026-09-10']),
          collection(
            'Garden waste',
            ['2026-09-11'],
            subscriptionRequired: true,
          ),
        ]),
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(1));
      expect(reminders.single.binNames, ['Black bin']);
      expect(scheduler.scheduled.single, hasLength(1));
      expect(scheduler.scheduled.single.single.binNames, ['Black bin']);
    });

    test('cancels when every collection needs a subscription', () async {
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: scheduleWith([
          collection(
            'Garden waste',
            ['2026-09-10'],
            subscriptionRequired: true,
          ),
        ]),
        enabled: true,
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });
  });

  group('ReminderSyncService launch re-sync', () {
    test('re-schedules from the schedule a previous session saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SettingsProvider(prefs);
      await first.saveSchedule(
        scheduleWith([collection('Black bin', ['2026-09-10'])]),
      );
      await first.setRemindersEnabled(true);

      // A cold start reads those values back from storage.
      final settings = SettingsProvider(prefs);
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      final reminders = await sync.sync(
        schedule: settings.savedSchedule,
        enabled: settings.remindersEnabled,
        reminderTime: settings.reminderTime,
      );

      expect(settings.remindersEnabled, isTrue);
      expect(reminders.single.fireAt, DateTime(2026, 9, 9, 19, 0));
      expect(scheduler.scheduled.single.single.binNames, ['Black bin']);
    });

    test('never re-schedules a provisional saved schedule', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SettingsProvider(prefs);
      await first.saveSchedule(Schedule(
        propertyId: 'p:4c5ee6c2f2c7c959',
        addressMatch: 'fuzzy',
        provisional: true,
        collections: [collection('Black bin', ['2026-09-10'])],
      ));
      await first.setRemindersEnabled(true);

      final settings = SettingsProvider(prefs);
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      await sync.sync(
        schedule: settings.savedSchedule,
        enabled: settings.remindersEnabled,
        reminderTime: settings.reminderTime,
      );

      expect(settings.savedSchedule?.provisional, isTrue);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });

    test('cancels on launch when reminders were left off', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SettingsProvider(prefs);
      await first.saveSchedule(
        scheduleWith([collection('Black bin', ['2026-09-10'])]),
      );

      final settings = SettingsProvider(prefs);
      final scheduler = FakeNotificationScheduler();
      final sync = ReminderSyncService(
        notifications: scheduler,
        now: () => now,
      );

      await sync.sync(
        schedule: settings.savedSchedule,
        enabled: settings.remindersEnabled,
        reminderTime: settings.reminderTime,
      );

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelAllCalls, 1);
    });
  });

  group('ReminderSyncService permissions', () {
    test('reports whether notification permission was granted', () async {
      final scheduler = FakeNotificationScheduler()..permissionGranted = false;
      final sync = ReminderSyncService(notifications: scheduler);

      expect(await sync.requestPermissions(), isFalse);
      expect(scheduler.permissionRequests, 1);
    });
  });
}

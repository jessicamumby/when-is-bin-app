import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

void main() {
  group('ReminderScheduler.nextReminder', () {
    test('returns the evening-before time for the next collection', () {
      // Collection on 2026-09-10 (a Thursday). Evening-before = 2026-09-09 19:00.
      final result = ReminderScheduler.nextReminder(
        collectionDate: DateTime(2026, 9, 10),
        now: DateTime(2026, 9, 1),
        reminderTime: ReminderTime.evening,
      );

      expect(result, DateTime(2026, 9, 9, 19, 0));
    });

    test('returns the morning-before time for the next collection', () {
      final result = ReminderScheduler.nextReminder(
        collectionDate: DateTime(2026, 9, 10),
        now: DateTime(2026, 9, 1),
        reminderTime: ReminderTime.morning,
      );

      expect(result, DateTime(2026, 9, 9, 9, 0));
    });

    test('skips a collection that is already past', () {
      // Collection on 2026-09-10, but "now" is 2026-09-11 (after it).
      final result = ReminderScheduler.nextReminder(
        collectionDate: DateTime(2026, 9, 10),
        now: DateTime(2026, 9, 11),
        reminderTime: ReminderTime.evening,
      );

      expect(result, isNull);
    });

    test('returns null when the reminder time has already passed today', () {
      // Collection tomorrow (2026-09-10), now is 2026-09-09 20:00 (after 19:00).
      final result = ReminderScheduler.nextReminder(
        collectionDate: DateTime(2026, 9, 10),
        now: DateTime(2026, 9, 9, 20, 0),
        reminderTime: ReminderTime.evening,
      );

      expect(result, isNull);
    });
  });

  group('ReminderScheduler.scheduleFor', () {
    test('produces one reminder per collection date, soonest first', () {
      final schedule = {
        'Black bin': ['2026-09-10', '2026-09-24'],
        'Blue bin': ['2026-09-17'],
      };

      final reminders = ReminderScheduler.scheduleFor(
        collections: schedule,
        now: DateTime(2026, 9, 1),
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(3));
      expect(reminders[0].collectionDate, DateTime(2026, 9, 10));
      expect(reminders[0].fireAt, DateTime(2026, 9, 9, 19, 0));
      expect(reminders[0].binNames, contains('Black bin'));
      expect(reminders[1].collectionDate, DateTime(2026, 9, 17));
      expect(reminders[2].collectionDate, DateTime(2026, 9, 24));
    });

    test('groups multiple bins collected on the same date into one reminder',
        () {
      final schedule = {
        'Black bin': ['2026-09-10'],
        'Blue bin': ['2026-09-10'],
      };

      final reminders = ReminderScheduler.scheduleFor(
        collections: schedule,
        now: DateTime(2026, 9, 1),
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(1));
      expect(reminders.first.binNames, containsAll(['Black bin', 'Blue bin']));
    });

    test('drops collection dates that are already past', () {
      final schedule = {
        'Black bin': ['2026-09-01', '2026-09-24'],
      };

      final reminders = ReminderScheduler.scheduleFor(
        collections: schedule,
        now: DateTime(2026, 9, 10),
        reminderTime: ReminderTime.evening,
      );

      expect(reminders, hasLength(1));
      expect(reminders.first.collectionDate, DateTime(2026, 9, 24));
    });
  });
}

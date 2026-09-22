import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

void main() {
  group('NotificationService', () {
    test('builds a notification title and body for a reminder', () {
      final reminder = Reminder(
        collectionDate: DateTime(2026, 9, 10),
        fireAt: DateTime(2026, 9, 9, 19, 0),
        binNames: const ['Black bin', 'Blue bin'],
      );

      final content = NotificationService.buildContent(reminder);

      expect(content.title, 'Bins out tomorrow');
      expect(content.body, contains('Black bin'));
      expect(content.body, contains('Blue bin'));
    });

    test('builds a singular body for a single bin', () {
      final reminder = Reminder(
        collectionDate: DateTime(2026, 9, 10),
        fireAt: DateTime(2026, 9, 9, 19, 0),
        binNames: const ['Black bin'],
      );

      final content = NotificationService.buildContent(reminder);

      expect(content.body, 'Put out the Black bin tomorrow.');
    });

    test('builds a plural body for multiple bins', () {
      final reminder = Reminder(
        collectionDate: DateTime(2026, 9, 10),
        fireAt: DateTime(2026, 9, 9, 19, 0),
        binNames: const ['Black bin', 'Blue bin', 'Garden waste'],
      );

      final content = NotificationService.buildContent(reminder);

      expect(content.body,
          'Put out the Black bin, Blue bin and Garden waste tomorrow.');
    });
  });
}

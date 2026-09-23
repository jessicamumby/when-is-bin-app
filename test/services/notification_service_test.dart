import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

class MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class MockAndroidNotifications extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

class MockIOSNotifications extends Mock
    implements IOSFlutterLocalNotificationsPlugin {}

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

  group('NotificationService.requestPermissions', () {
    test('returns false when the platform denies permission', () async {
      final plugin = MockNotificationsPlugin();
      final android = MockAndroidNotifications();
      when(() => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>())
          .thenReturn(android);
      when(() => android.requestNotificationsPermission())
          .thenAnswer((_) async => false);

      final service = NotificationService(plugin: plugin);

      expect(await service.requestPermissions(), isFalse);
    });

    test('returns true when the platform grants permission', () async {
      final plugin = MockNotificationsPlugin();
      final android = MockAndroidNotifications();
      when(() => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>())
          .thenReturn(android);
      when(() => android.requestNotificationsPermission())
          .thenAnswer((_) async => true);

      final service = NotificationService(plugin: plugin);

      expect(await service.requestPermissions(), isTrue);
    });

    test('treats an unknown platform verdict as granted', () async {
      // Android returns null when it cannot report a verdict.
      final plugin = MockNotificationsPlugin();
      final android = MockAndroidNotifications();
      when(() => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>())
          .thenReturn(android);
      when(() => android.requestNotificationsPermission())
          .thenAnswer((_) async => null);

      final service = NotificationService(plugin: plugin);

      expect(await service.requestPermissions(), isTrue);
    });

    test('asks the iOS implementation when Android is not the platform',
        () async {
      final plugin = MockNotificationsPlugin();
      final ios = MockIOSNotifications();
      when(() => plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>())
          .thenReturn(ios);
      when(() => ios.requestPermissions(alert: true, badge: true, sound: true))
          .thenAnswer((_) async => false);

      final service = NotificationService(plugin: plugin);

      expect(await service.requestPermissions(), isFalse);
    });

    test('does not block a platform with no permission gate', () async {
      final plugin = MockNotificationsPlugin();

      final service = NotificationService(plugin: plugin);

      expect(await service.requestPermissions(), isTrue);
    });
  });

  group('NotificationService time zone', () {
    test('builds the fire time in the configured local zone', () {
      NotificationService.configureLocalTimeZone(zoneName: 'Europe/London');

      final fireAt =
          NotificationService.toTZDateTime(DateTime(2026, 7, 15, 19, 0));

      // The reminder is 7pm *local*: the wall-clock fields must survive.
      expect(fireAt.location.name, 'Europe/London');
      expect(fireAt.hour, 19);
      expect(fireAt.minute, 0);
      // July in London is BST, an hour ahead of UTC.
      expect(fireAt.timeZoneOffset, const Duration(hours: 1));
    });

    test('keeps the reminder at the same wall-clock hour across DST', () {
      NotificationService.configureLocalTimeZone(zoneName: 'Europe/London');

      // UK clocks go back on 2026-10-25, so this date is GMT.
      final fireAt =
          NotificationService.toTZDateTime(DateTime(2026, 10, 27, 19, 0));

      expect(fireAt.hour, 19);
      expect(fireAt.timeZoneOffset, Duration.zero);
    });

    test('falls back to the UK zone for an unusable device zone name', () {
      // DateTime.timeZoneName gives abbreviations like "BST", which are not
      // in the time zone database.
      NotificationService.configureLocalTimeZone(zoneName: 'BST');

      expect(tz.local.name, 'Europe/London');
    });
  });
}

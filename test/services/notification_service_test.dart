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

class _FakeInitializationSettings extends Fake
    implements InitializationSettings {}

class _FakeTZDateTime extends Fake implements tz.TZDateTime {}

class _FakeNotificationDetails extends Fake implements NotificationDetails {}

/// A fire time at [utc], built in the UK zone.
Matcher _firesAt(DateTime utc) => isA<tz.TZDateTime>()
    .having((d) => d.location.name, 'location', 'Europe/London')
    .having((d) => d.toUtc(), 'instant', utc);

/// The reminder channel and the default iOS presentation.
final Matcher _reminderDetails = isA<NotificationDetails>()
    .having((d) => d.android?.channelId, 'Android channel', 'bin_reminders')
    .having((d) => d.android?.importance, 'importance', Importance.high)
    .having((d) => d.android?.priority, 'priority', Priority.high)
    .having((d) => d.iOS, 'iOS details', isNotNull);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeInitializationSettings());
    registerFallbackValue(_FakeTZDateTime());
    registerFallbackValue(_FakeNotificationDetails());
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });

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
      NotificationService.configureLocalTimeZone();

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
      NotificationService.configureLocalTimeZone();

      // UK clocks go back on 2026-10-25, so this date is GMT.
      final fireAt =
          NotificationService.toTZDateTime(DateTime(2026, 10, 27, 19, 0));

      expect(fireAt.hour, 19);
      expect(fireAt.timeZoneOffset, Duration.zero);
    });

    test('always builds reminders on UK time', () {
      NotificationService.configureLocalTimeZone();

      expect(tz.local.name, 'Europe/London');
    });

    test('a summer reminder scheduled in winter still fires at 7pm BST', () {
      // In winter the phone reports its zone as "GMT", which the time zone
      // database reads as a fixed zone with no daylight saving. Reminders
      // must not inherit that: 7pm in April is 18:00 UTC, not 19:00.
      NotificationService.configureLocalTimeZone();

      final fireAt =
          NotificationService.toTZDateTime(DateTime(2027, 4, 10, 19, 0));

      expect(fireAt.hour, 19);
      expect(fireAt.toUtc().hour, 18);
    });
  });

  group('NotificationService plugin calls', () {
    test('initialises without asking for any permission', () async {
      // Permission is asked for in onboarding, never at launch.
      final plugin = MockNotificationsPlugin();
      when(() => plugin.initialize(settings: any(named: 'settings')))
          .thenAnswer((_) async => true);

      await NotificationService(plugin: plugin).init();

      final captured = verify(
        () => plugin.initialize(settings: captureAny(named: 'settings')),
      ).captured;
      expect(captured, [
        isA<InitializationSettings>()
            .having((s) => s.android?.defaultIcon, 'Android icon',
                '@mipmap/ic_launcher')
            .having((s) => s.iOS?.requestAlertPermission, 'alert', isFalse)
            .having((s) => s.iOS?.requestBadgePermission, 'badge', isFalse)
            .having((s) => s.iOS?.requestSoundPermission, 'sound', isFalse),
      ]);
    });

    test('replaces every reminder with one UK-time notification each',
        () async {
      NotificationService.configureLocalTimeZone();
      final plugin = MockNotificationsPlugin();
      when(() => plugin.cancelAll()).thenAnswer((_) async {});
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
        ),
      ).thenAnswer((_) async {});

      await NotificationService(plugin: plugin).scheduleReminders([
        // After the October clock change: 7pm GMT is 19:00 UTC.
        Reminder(
          collectionDate: DateTime(2026, 10, 28),
          fireAt: DateTime(2026, 10, 27, 19, 0),
          binNames: const ['Black bin'],
        ),
        // In BST: 9am is 08:00 UTC.
        Reminder(
          collectionDate: DateTime(2027, 4, 10),
          fireAt: DateTime(2027, 4, 9, 9, 0),
          binNames: const ['Blue bin', 'Garden waste'],
        ),
      ]);

      verifyInOrder([
        () => plugin.cancelAll(),
        () => plugin.zonedSchedule(
              id: 0,
              title: 'Bins out tomorrow',
              body: 'Put out the Black bin tomorrow.',
              scheduledDate: any(
                named: 'scheduledDate',
                that: _firesAt(DateTime.utc(2026, 10, 27, 19)),
              ),
              notificationDetails: any(
                named: 'notificationDetails',
                that: _reminderDetails,
              ),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            ),
        () => plugin.zonedSchedule(
              id: 1,
              title: 'Bins out tomorrow',
              body: 'Put out the Blue bin and Garden waste tomorrow.',
              scheduledDate: any(
                named: 'scheduledDate',
                that: _firesAt(DateTime.utc(2027, 4, 9, 8)),
              ),
              notificationDetails: any(
                named: 'notificationDetails',
                that: _reminderDetails,
              ),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            ),
      ]);
      verifyNoMoreInteractions(plugin);
    });

    test('clears every reminder when there are none to schedule', () async {
      final plugin = MockNotificationsPlugin();
      when(() => plugin.cancelAll()).thenAnswer((_) async {});

      await NotificationService(plugin: plugin).scheduleReminders(const []);

      verify(() => plugin.cancelAll()).called(1);
      verifyNoMoreInteractions(plugin);
    });
  });
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_scheduler.dart';

/// The title and body shown for a reminder notification.
class NotificationContent {
  const NotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

/// The notification operations the reminder sync depends on.
///
/// [ReminderSyncService] talks to this rather than to
/// [FlutterLocalNotificationsPlugin] directly, so the scheduling rules can be
/// tested without a real device.
abstract class NotificationScheduler {
  /// Ask the OS for permission to post notifications. Returns whether it was
  /// granted; platforms without a permission gate return true.
  Future<bool> requestPermissions();

  /// Replace any existing reminders with [reminders].
  Future<void> scheduleReminders(List<Reminder> reminders);

  /// Remove every scheduled reminder.
  Future<void> cancelAll();
}

/// Builds and schedules local notifications for bin collection reminders.
class NotificationService implements NotificationScheduler {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'bin_reminders';
  static const _channelName = 'Bin collection reminders';

  /// The zone reminders are built in when the device's own zone cannot be
  /// resolved. The service only covers UK councils, so Europe/London is correct
  /// for every household it serves.
  static const fallbackTimeZone = 'Europe/London';

  /// Point `tz.local` at the device's zone so reminders fire at the right
  /// wall-clock time.
  ///
  /// The `timezone` package defaults `tz.local` to UTC, which would fire every
  /// reminder an hour late through BST. `DateTime.timeZoneName` only yields an
  /// abbreviation ("BST", "GMT"), not an IANA name, so the lookup is
  /// best-effort and falls back to [fallbackTimeZone].
  static void configureLocalTimeZone({String? zoneName}) {
    tzdata.initializeTimeZones();
    final name = zoneName ?? DateTime.now().timeZoneName;
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } on tz.LocationNotFoundException {
      tz.setLocalLocation(tz.getLocation(fallbackTimeZone));
    }
  }

  /// The instant a wall-clock [local] time refers to, in the configured zone.
  static tz.TZDateTime toTZDateTime(DateTime local) {
    final location = tz.local;
    return tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }

  /// Builds the notification title and body for a reminder.
  static NotificationContent buildContent(Reminder reminder) {
    final bins = reminder.binNames;
    final body = bins.length == 1
        ? 'Put out the ${bins.first} tomorrow.'
        : 'Put out the ${_joinBins(bins)} tomorrow.';
    return NotificationContent(title: 'Bins out tomorrow', body: body);
  }

  static String _joinBins(List<String> bins) {
    if (bins.length == 2) return '${bins[0]} and ${bins[1]}';
    return '${bins.sublist(0, bins.length - 1).join(', ')} and ${bins.last}';
  }

  /// Initialise the plugin and the time zone reminders are built in.
  ///
  /// Permission is requested explicitly (e.g. during onboarding), not at
  /// startup.
  Future<void> init() async {
    configureLocalTimeZone();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );
  }

  @override
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    final macOS = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macOS != null) {
      return await macOS.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    // No permission gate on this platform — don't block the reminder.
    return true;
  }

  /// Schedule one notification per reminder, cancelling any previous ones.
  @override
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    await _plugin.cancelAll();
    for (var i = 0; i < reminders.length; i++) {
      final reminder = reminders[i];
      final content = buildContent(reminder);
      await _plugin.zonedSchedule(
        i,
        content.title,
        content.body,
        toTZDateTime(reminder.fireAt),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Reminders to put your bins out',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
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

/// Builds and schedules local notifications for bin collection reminders.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'bin_reminders';
  static const _channelName = 'Bin collection reminders';

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

  /// Initialise the plugin and request notification permission.
  Future<void> init() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
    );
  }

  /// Schedule one notification per reminder, cancelling any previous ones.
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    await _plugin.cancelAll();
    for (var i = 0; i < reminders.length; i++) {
      final reminder = reminders[i];
      final content = buildContent(reminder);
      await _plugin.zonedSchedule(
        i,
        content.title,
        content.body,
        _toTZDateTime(reminder.fireAt),
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

  Future<void> cancelAll() => _plugin.cancelAll();

  tz.TZDateTime _toTZDateTime(DateTime local) {
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
}

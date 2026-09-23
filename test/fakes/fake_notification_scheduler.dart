import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

/// Records what the reminder sync asked the notification layer to do, so unit
/// and widget tests never touch the real notifications plugin.
class FakeNotificationScheduler implements NotificationScheduler {
  final scheduled = <List<Reminder>>[];
  int cancelAllCalls = 0;
  int permissionRequests = 0;
  bool permissionGranted = true;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    scheduled.add(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
  }
}

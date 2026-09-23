import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

/// A controllable fake of [NotificationService] that records permission
/// requests and scheduling calls without touching the platform plugin.
class FakeNotificationService extends NotificationService {
  int requestPermissionCount = 0;
  int scheduleCount = 0;
  List<Reminder>? lastReminders;

  @override
  Future<bool> requestPermissions() async {
    requestPermissionCount++;
    return true;
  }

  @override
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    scheduleCount++;
    lastReminders = reminders;
  }
}
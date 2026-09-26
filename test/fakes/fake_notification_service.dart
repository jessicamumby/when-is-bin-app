import 'dart:async';

import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

/// A controllable fake of [NotificationService] that records permission
/// requests and scheduling calls without touching the platform plugin.
class FakeNotificationService extends NotificationService {
  int requestPermissionCount = 0;
  int scheduleCount = 0;
  List<Reminder>? lastReminders;

  /// When true, [requestPermissions] never resolves — the orphaned Android
  /// permission callback that strands onboarding.
  bool hangPermissionRequest = false;

  @override
  Future<bool> requestPermissions() {
    requestPermissionCount++;
    if (hangPermissionRequest) {
      return Completer<bool>().future;
    }
    return Future.value(true);
  }

  @override
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    scheduleCount++;
    lastReminders = reminders;
  }
}
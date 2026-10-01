import 'dart:async';

import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

/// Records what the reminder sync asked the notification layer to do, so unit
/// and widget tests never touch the real notifications plugin.
class FakeNotificationScheduler implements NotificationScheduler {
  final scheduled = <List<Reminder>>[];
  int cancelAllCalls = 0;
  int permissionRequests = 0;
  bool permissionGranted = true;

  /// Whether the OS will actually keep what is scheduled. iOS silently drops
  /// reminders added before the user has allowed notifications: the add call
  /// still succeeds, but nothing is left pending.
  bool authorised = true;

  /// The reminders the OS is holding, i.e. the ones that will actually fire.
  List<Reminder> pending = const [];

  /// When true, [requestPermissions] never resolves — the orphaned Android
  /// permission callback.
  bool hangPermissionRequest = false;

  /// When true, [scheduleReminders] never resolves — a hung zonedSchedule.
  bool hangOnSchedule = false;

  /// When set, [scheduleReminders] only lands its reminders once this
  /// completes — a platform call still in flight.
  Completer<void>? holdSchedule;

  @override
  Future<bool> requestPermissions() {
    permissionRequests++;
    if (hangPermissionRequest) {
      return Completer<bool>().future;
    }
    return Future.value(permissionGranted);
  }

  @override
  Future<void> scheduleReminders(List<Reminder> reminders) async {
    scheduled.add(reminders);
    if (hangOnSchedule) {
      return Completer<void>().future;
    }
    final hold = holdSchedule;
    if (hold != null) await hold.future;
    pending = authorised ? List.of(reminders) : const [];
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    pending = const [];
  }
}

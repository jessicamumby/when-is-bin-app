import 'dart:async';

import '../models/schedule.dart';
import 'notification_service.dart';
import 'reminder_scheduler.dart';

/// Re-derives the bin reminders that should be on the device and applies them.
///
/// The schedule is only as fresh as the last lookup, and the app can sit
/// closed for weeks, so the reminders are recomputed from the saved schedule
/// on launch (and whenever the user flips the switch) instead of being trusted
/// to survive untouched.
class ReminderSyncService {
  ReminderSyncService({
    required NotificationScheduler notifications,
    DateTime Function()? now,
    this.permissionTimeout = const Duration(seconds: 5),
  })  : _notifications = notifications,
        _now = now ?? DateTime.now;

  final NotificationScheduler _notifications;
  final DateTime Function() _now;

  /// How long to wait for the OS permission verdict before treating the
  /// request as denied. An Android activity recreation mid-request can orphan
  /// the permission callback so its future never resolves; an unbounded wait
  /// would strand onboarding and the Settings toggle on a dialog that already
  /// closed.
  final Duration permissionTimeout;

  /// Ask the OS for permission to post notifications; true when granted.
  ///
  /// Bounded: a platform that never answers is treated as denied rather than
  /// hanging the caller, and a platform that errors is treated the same so a
  /// permission hiccup never blocks the reminder flow.
  Future<bool> requestPermissions() async {
    try {
      return await _notifications.requestPermissions().timeout(permissionTimeout);
    } catch (_) {
      return false;
    }
  }

  /// Apply [enabled] to [schedule]: schedule one reminder per upcoming
  /// collection, or cancel everything when reminders are off or there is
  /// nothing left to remind about.
  ///
  /// Returns the reminders now scheduled (empty when everything was cancelled).
  Future<List<Reminder>> sync({
    required Schedule? schedule,
    required bool enabled,
    required ReminderTime reminderTime,
  }) async {
    final reminders =
        _remindersFor(schedule, enabled: enabled, reminderTime: reminderTime);
    if (reminders == null || reminders.isEmpty) {
      await _notifications.cancelAll();
      return const [];
    }
    await _notifications.scheduleReminders(reminders);
    return reminders;
  }

  /// The reminders to schedule, or null when nothing should be scheduled and
  /// any existing reminders must be cancelled.
  List<Reminder>? _remindersFor(
    Schedule? schedule, {
    required bool enabled,
    required ReminderTime reminderTime,
  }) {
    if (!enabled || schedule == null) return null;
    // Provisional dates are estimates the council has not confirmed yet; the
    // API contract forbids reminding anyone about them.
    if (schedule.provisional) return null;

    final collections = <String, List<String>>{};
    for (final collection in schedule.collections) {
      // A charged garden-waste service the household may not subscribe to: the
      // bin never goes out, so never remind about it.
      if (collection.subscriptionRequired) continue;
      collections[collection.name] = collection.dates;
    }

    return ReminderScheduler.scheduleFor(
      collections: collections,
      now: _now(),
      reminderTime: reminderTime,
    );
  }
}

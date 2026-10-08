import '../models/schedule.dart';
import '../providers/settings_provider.dart';
import 'reminder_sync_service.dart';
import 'schedule_refresh_service.dart';

/// What one re-check of the saved schedule did.
sealed class RecheckOutcome {
  const RecheckOutcome();
}

/// No schedule is saved, so there is nothing to re-check.
final class NothingToRecheck extends RecheckOutcome {
  const NothingToRecheck();
}

/// The last completed check is recent enough; the API was not asked.
final class RecheckNotDue extends RecheckOutcome {
  const RecheckNotDue(this.lastCheckedAt);

  final DateTime lastCheckedAt;
}

/// The API answered and the saved dates stand: a 304, or a property the
/// council has stopped answering for, whose saved copy is still the best we
/// have.
final class ScheduleStillCurrent extends RecheckOutcome {
  const ScheduleStillCurrent();
}

/// The council moved its dates. The new schedule is saved and the reminders
/// follow it.
final class ScheduleUpdated extends RecheckOutcome {
  const ScheduleUpdated(this.schedule);

  final Schedule schedule;
}

/// The check could not be completed (rate limit, dead connection). The saved
/// schedule stands, and the check stays due for the next trigger.
final class RecheckFailed extends RecheckOutcome {
  const RecheckFailed();
}

/// Re-checks the saved schedule and keeps the reminders in step with it.
///
/// One path for every trigger: a cold launch (forced), the app coming back to
/// the foreground, and the periodic background task. A council can move a
/// collection day at any time (Christmas is the usual one), and someone who
/// relies on the reminders may not open the app for weeks, so the schedule
/// cannot only be checked when the app happens to cold-start.
class ScheduleRecheckService {
  ScheduleRecheckService({
    required ScheduleRefreshService refresh,
    required ReminderSyncService reminderSync,
    DateTime Function()? now,
  })  : _refresh = refresh,
        _reminderSync = reminderSync,
        _now = now ?? DateTime.now;

  /// How long a completed check stays good enough for a resume or a
  /// background run.
  ///
  /// Councils publish changes days or weeks ahead, and a reminder fires the
  /// day before, so a check every half-day is fresh enough to catch a moved
  /// collection before its reminder. It also caps a device at roughly two
  /// conditional requests a day however often the app is opened, which keeps
  /// a free API's load down.
  static const recheckInterval = Duration(hours: 12);

  final ScheduleRefreshService _refresh;
  final ReminderSyncService _reminderSync;
  final DateTime Function() _now;

  /// Re-check [settings]' saved schedule, unless it was checked within
  /// [recheckInterval]; [force] skips that limit (a cold launch).
  ///
  /// Never throws: [ScheduleRefreshService.refresh] already turns API failures
  /// into a result, and the reminder sync is time-limited.
  Future<RecheckOutcome> recheck(
    SettingsProvider settings, {
    bool force = false,
  }) async {
    final propertyToken = settings.savedPropertyId;
    final cached = settings.savedSchedule;
    if (propertyToken == null || cached == null) {
      return const NothingToRecheck();
    }

    final lastCheckedAt = settings.scheduleCheckedAt;
    if (!force &&
        lastCheckedAt != null &&
        _now().difference(lastCheckedAt) < recheckInterval) {
      return RecheckNotDue(lastCheckedAt);
    }

    final result = await _refresh.refresh(
      propertyToken: propertyToken,
      cached: cached,
      etag: settings.savedScheduleEtag,
    );
    final updated = result.schedule;
    switch (result.status) {
      case ScheduleRefreshStatus.failed:
        return const RecheckFailed();
      case ScheduleRefreshStatus.unchanged:
      case ScheduleRefreshStatus.missing:
        await settings.markScheduleChecked();
        return const ScheduleStillCurrent();
      case ScheduleRefreshStatus.updated:
        if (updated == null) return const RecheckFailed();
        await settings.saveSchedule(updated, etag: result.etag);
        await _reminderSync.sync(
          schedule: updated,
          enabled: settings.remindersEnabled,
          reminderTime: settings.reminderTime,
        );
        return ScheduleUpdated(updated);
    }
  }
}

/// When the user wants their reminder: the morning before (9am) or the
/// evening before (7pm) the collection day.
enum ReminderTime {
  morning(9, 0),
  evening(19, 0);

  const ReminderTime(this.hour, this.minute);

  final int hour;
  final int minute;
}

/// A single scheduled reminder for one collection date.
class Reminder {
  const Reminder({
    required this.collectionDate,
    required this.fireAt,
    required this.binNames,
  });

  final DateTime collectionDate;
  final DateTime fireAt;
  final List<String> binNames;
}

/// Computes when local notifications should fire for a set of collection
/// dates, given the user's chosen reminder time.
class ReminderScheduler {
  const ReminderScheduler();

  /// The reminder time for a single collection date, or null if it has
  /// already passed.
  static DateTime? nextReminder({
    required DateTime collectionDate,
    required DateTime now,
    required ReminderTime reminderTime,
  }) {
    final fireAt = DateTime(
      collectionDate.year,
      collectionDate.month,
      collectionDate.day - 1,
      reminderTime.hour,
      reminderTime.minute,
    );
    return fireAt.isAfter(now) ? fireAt : null;
  }

  /// Builds one reminder per collection date, grouping bins collected on the
  /// same date, sorted soonest first. Past dates are dropped.
  static List<Reminder> scheduleFor({
    required Map<String, List<String>> collections,
    required DateTime now,
    required ReminderTime reminderTime,
  }) {
    // Map collection date -> set of bin names.
    final byDate = <DateTime, Set<String>>{};
    collections.forEach((binName, dates) {
      for (final date in dates) {
        final parsed = DateTime.parse(date);
        byDate.putIfAbsent(parsed, () => {}).add(binName);
      }
    });

    final reminders = <Reminder>[];
    final sortedDates = byDate.keys.toList()..sort();
    for (final date in sortedDates) {
      final fireAt = nextReminder(
        collectionDate: date,
        now: now,
        reminderTime: reminderTime,
      );
      if (fireAt == null) continue;
      reminders.add(Reminder(
        collectionDate: date,
        fireAt: fireAt,
        binNames: byDate[date]!.toList()..sort(),
      ));
    }
    return reminders;
  }
}

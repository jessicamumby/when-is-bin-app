/// When the user wants their reminder, always on the day before the
/// collection: morning (9am), evening (7pm) or late evening (10pm).
///
/// The value's name is what `SettingsProvider` stores, so never rename one.
enum ReminderTime {
  morning(9, 0, 'Morning before', '9:00am'),
  evening(19, 0, 'Evening before', '7:00pm'),
  lateEvening(22, 0, 'Late evening', '10:00pm');

  const ReminderTime(this.hour, this.minute, this.title, this.clock);

  final int hour;
  final int minute;

  /// How the choice is named, such as "Evening before".
  final String title;

  /// The time as the app writes it, such as "7:00pm".
  final String clock;

  /// The label on the option the user picks, such as
  /// "Evening before (7:00pm)".
  String get optionLabel => '$title ($clock)';
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

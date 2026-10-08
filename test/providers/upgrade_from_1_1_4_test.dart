import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

/// Every live user upgrades with what an older version saved. The fixture is
/// the raw stored values 1.1.4's own SettingsProvider wrote for a returning
/// user (address, schedule, ETag, reminders on at 9am, onboarded), captured by
/// running 1.1.4's code. If a later change renames a key or changes how one is
/// read, this fails before an upgrade drops someone's address or reminders.
void main() {
  test('reads everything 1.1.4 saved', () async {
    final stored = (jsonDecode(
      File('test/fixtures/prefs_written_by_1_1_4.json').readAsStringSync(),
    ) as Map<String, dynamic>)
        .cast<String, Object>();
    SharedPreferences.setMockInitialValues(stored);

    final settings = SettingsProvider(await SharedPreferences.getInstance());

    expect(settings.isOnboarded, isTrue);
    expect(settings.savedAddress, 'Fixture address');
    expect(settings.savedPostcode, 'CB2 3QD');
    expect(settings.savedPropertyId, 'p:8ccd92739644bc77');
    expect(settings.savedScheduleEtag, '"v1-etag"');
    expect(settings.remindersEnabled, isTrue);
    expect(settings.reminderTime, ReminderTime.morning);

    final schedule = settings.savedSchedule;
    expect(schedule, isNotNull);
    expect(schedule?.byDate.map((e) => e.date),
        ['2026-10-11', '2026-10-18', '2026-10-25']);
    expect(schedule?.byDate[1].collections.single.name, 'Blue bin');
    expect(schedule?.calendarUrl, 'https://whenisbins.com/verify-fixture.ics');
    expect(schedule?.notes, 'Bank holiday collections may move.');

    // 1.1.4 never recorded a check, so the first launch after the upgrade
    // re-checks rather than trusting a stamp that isn't there.
    expect(settings.scheduleCheckedAt, isNull);
  });
}

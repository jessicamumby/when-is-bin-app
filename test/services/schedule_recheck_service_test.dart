import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';
import 'package:when_is_bin_app/services/schedule_recheck_service.dart';
import 'package:when_is_bin_app/services/schedule_refresh_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../fakes/fake_api.dart';
import '../fakes/fake_notification_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Collections a few days out, so reminders are always due whenever the
  // suite runs.
  final today = DateTime.now();
  String isoIn(int days) =>
      DateFormat('yyyy-MM-dd').format(today.add(Duration(days: days)));

  Schedule schedule(String date, {String bin = 'Black bin'}) => Schedule(
        propertyId: 'p:4c5ee6c2f2c7c959',
        addressMatch: 'exact',
        collections: [
          Collection(name: bin, wasteType: 'refuse', dates: [date]),
        ],
      );

  late FakeWhenIsBinsApi api;
  late FakeNotificationScheduler notifications;
  late SettingsProvider settings;
  late DateTime now;

  ScheduleRecheckService service() => ScheduleRecheckService(
        refresh: ScheduleRefreshService(api: api),
        reminderSync: ReminderSyncService(notifications: notifications),
        now: () => now,
      );

  /// A saved address and schedule, last checked [checkedAgo] before [now].
  Future<void> saved({
    Duration? checkedAgo,
    bool reminders = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final checkedAt = checkedAgo == null ? now : now.subtract(checkedAgo);
    final seed = SettingsProvider(prefs, now: () => checkedAt);
    await seed.saveAddress(
      address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      postcode: 'CB4 2HX',
      propertyId: 'p:4c5ee6c2f2c7c959',
    );
    await seed.saveSchedule(schedule(isoIn(3)), etag: '"v1"');
    await seed.setRemindersEnabled(reminders);
    settings = SettingsProvider(prefs, now: () => now);
  }

  setUp(() {
    api = FakeWhenIsBinsApi();
    notifications = FakeNotificationScheduler();
    now = DateTime.utc(2026, 10, 5, 18);
  });

  group('ScheduleRecheckService', () {
    test('does nothing when no schedule is saved', () async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsProvider(await SharedPreferences.getInstance());

      final outcome = await service().recheck(settings);

      expect(outcome, isA<NothingToRecheck>());
      expect(api.scheduleCheckCalls, 0);
    });

    test('does not ask the API again within the recheck interval', () async {
      await saved(checkedAgo: const Duration(hours: 11, minutes: 59));

      final outcome = await service().recheck(settings);

      expect(outcome, isA<RecheckNotDue>());
      expect(api.scheduleCheckCalls, 0);
    });

    test('asks again once the recheck interval has passed', () async {
      await saved(checkedAgo: ScheduleRecheckService.recheckInterval);

      final outcome = await service().recheck(settings);

      expect(outcome, isA<ScheduleStillCurrent>());
      expect(api.scheduleCheckCalls, 1);
      expect(api.lastScheduleEtag, '"v1"');
    });

    test('a forced recheck ignores the interval', () async {
      await saved(checkedAgo: const Duration(minutes: 1));

      final outcome = await service().recheck(settings, force: true);

      expect(outcome, isA<ScheduleStillCurrent>());
      expect(api.scheduleCheckCalls, 1);
    });

    test('a schedule never checked is due', () async {
      SharedPreferences.setMockInitialValues({
        'saved_property_id': 'p:4c5ee6c2f2c7c959',
      });
      final prefs = await SharedPreferences.getInstance();
      // Written by a build from before check times were stored.
      await prefs.setString(
        'saved_schedule',
        '{"property_id":"p:4c5ee6c2f2c7c959","collections":[]}',
      );
      settings = SettingsProvider(prefs, now: () => now);
      expect(settings.scheduleCheckedAt, isNull);

      await service().recheck(settings);

      expect(api.scheduleCheckCalls, 1);
    });

    test('an unchanged schedule records the check and keeps the dates',
        () async {
      await saved(checkedAgo: const Duration(days: 2));
      api.scheduleCheck = const ScheduleCheck.unchanged(etag: '"v1"');

      final outcome = await service().recheck(settings);

      expect(outcome, isA<ScheduleStillCurrent>());
      expect(settings.scheduleCheckedAt, now);
      expect(settings.savedCollections.single.dates, [isoIn(3)]);
      // Nothing moved, so the reminders on the device stand.
      expect(notifications.scheduled, isEmpty);
    });

    test('a schedule the council no longer answers for keeps the saved copy',
        () async {
      await saved(checkedAgo: const Duration(days: 2));
      api.scheduleCheck = const ScheduleCheck.missing();

      final outcome = await service().recheck(settings);

      expect(outcome, isA<ScheduleStillCurrent>());
      expect(settings.savedCollections.single.dates, [isoIn(3)]);
    });

    test('a moved collection is saved and the reminders follow it', () async {
      await saved(checkedAgo: const Duration(days: 2));
      final moved = schedule(isoIn(5), bin: 'Blue bin');
      api.scheduleCheck = ScheduleCheck.updated(moved, etag: '"v2"');

      final outcome = await service().recheck(settings);

      expect(outcome, isA<ScheduleUpdated>());
      expect((outcome as ScheduleUpdated).schedule.collections.single.name,
          'Blue bin');
      expect(settings.savedCollections.single.dates, [isoIn(5)]);
      expect(settings.savedScheduleEtag, '"v2"');
      expect(settings.scheduleCheckedAt, now);
      expect(notifications.pending.single.binNames, ['Blue bin']);
    });

    test('a moved collection with reminders off schedules nothing', () async {
      await saved(checkedAgo: const Duration(days: 2), reminders: false);
      api.scheduleCheck =
          ScheduleCheck.updated(schedule(isoIn(5)), etag: '"v2"');

      await service().recheck(settings);

      expect(notifications.pending, isEmpty);
    });

    test('a failed check keeps the saved copy and stays due', () async {
      // A rate limit or a dead connection must not count as a check, or the
      // next attempt would wait out a whole interval for nothing.
      await saved(checkedAgo: const Duration(days: 2));
      final checkedBefore = settings.scheduleCheckedAt;
      api.scheduleCheckError = const ApiException(
        statusCode: 429,
        problem: 'rate_limited',
      );

      final outcome = await service().recheck(settings);

      expect(outcome, isA<RecheckFailed>());
      expect(settings.scheduleCheckedAt, checkedBefore);
      expect(settings.savedCollections.single.dates, [isoIn(3)]);
      expect(notifications.scheduled, isEmpty);
    });
  });
}

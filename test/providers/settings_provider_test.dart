import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

Schedule buildSchedule() {
  return const Schedule(
    propertyId: 'p:4c5ee6c2f2c7c959',
    addressMatch: 'exact',
    collections: [
      Collection(
        name: 'Black bin',
        wasteType: 'refuse',
        dates: ['2026-09-10', '2026-09-24'],
        datesComplete: true,
      ),
    ],
    byDate: [
      ByDateEntry(
        date: '2026-09-10',
        weekday: 'Thursday',
        collections: [
          ByDateCollection(name: 'Black bin', wasteType: 'refuse'),
        ],
      ),
    ],
    calendarUrl: 'https://whenisbins.com/100023336956.ics',
    retrievedAt: '2026-09-07T09:00:01Z',
  );
}

/// A schedule whose dates the council has not confirmed yet.
Schedule provisionalSchedule() {
  return const Schedule(
    propertyId: 'p:4c5ee6c2f2c7c959',
    addressMatch: 'fuzzy',
    provisional: true,
    collections: [
      Collection(
        name: 'Black bin',
        wasteType: 'refuse',
        dates: ['2026-09-10', '2026-09-24'],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider', () {
    test('defaults to evening reminder, no saved address, not onboarded',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.reminderTime, ReminderTime.evening);
      expect(provider.savedAddress, isNull);
      expect(provider.savedPostcode, isNull);
      expect(provider.isOnboarded, isFalse);
    });

    test('markOnboarded persists the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.markOnboarded();

      expect(provider.isOnboarded, isTrue);
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.isOnboarded, isTrue);
    });

    test('persists a chosen reminder time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.setReminderTime(ReminderTime.morning);

      expect(provider.reminderTime, ReminderTime.morning);
      // A fresh provider reads the persisted value.
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.reminderTime, ReminderTime.morning);
    });

    test('persists a saved address and postcode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.saveAddress(
        address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
        postcode: 'CB4 2HX',
        propertyId: 'p:4c5ee6c2f2c7c959',
      );

      expect(provider.savedAddress, '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX');
      expect(provider.savedPostcode, 'CB4 2HX');
      expect(provider.savedPropertyId, 'p:4c5ee6c2f2c7c959');

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.savedAddress, '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX');
      expect(reloaded.savedPostcode, 'CB4 2HX');
      expect(reloaded.savedPropertyId, 'p:4c5ee6c2f2c7c959');
    });

    test('clears the saved address', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveAddress(
        address: '1 Test Road',
        postcode: 'CB4 2HX',
        propertyId: 'p:abc',
      );

      await provider.clearSavedAddress();

      expect(provider.savedAddress, isNull);
      expect(provider.savedPostcode, isNull);
      expect(provider.savedPropertyId, isNull);
    });
  });

  group('SettingsProvider reminders', () {
    test('reminders are off by default', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.remindersEnabled, isFalse);
    });

    test('persists the reminder-enabled flag across a cold start', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.setRemindersEnabled(true);

      expect(provider.remindersEnabled, isTrue);
      // A fresh provider (cold start) reads the same value back.
      expect(SettingsProvider(prefs).remindersEnabled, isTrue);

      await provider.setRemindersEnabled(false);

      expect(provider.remindersEnabled, isFalse);
      expect(SettingsProvider(prefs).remindersEnabled, isFalse);
    });

    test('reads a persisted enabled flag at construction', () async {
      SharedPreferences.setMockInitialValues({'reminders_enabled': true});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.remindersEnabled, isTrue);
    });

    test('notifies listeners when the reminder flag changes', () async {
      SharedPreferences.setMockInitialValues({});
      final provider =
          SettingsProvider(await SharedPreferences.getInstance());
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setRemindersEnabled(true);

      expect(notifications, 1);
    });
  });

  group('SettingsProvider saved schedule', () {
    test('has no saved schedule by default', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.hasSavedSchedule, isFalse);
      expect(provider.savedSchedule, isNull);
      expect(provider.savedAddressMatch, isNull);
      expect(provider.savedCollections, isEmpty);
      expect(provider.savedByDate, isEmpty);
      expect(provider.savedCalendarUrl, isNull);
      expect(provider.savedRetrievedAt, isNull);
    });

    test('persists the schedule data needed to render offline', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.saveSchedule(buildSchedule());

      expect(provider.hasSavedSchedule, isTrue);
      expect(provider.savedPropertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.savedAddressMatch, 'exact');
      expect(provider.savedCollections, hasLength(1));
      expect(provider.savedCollections.single.name, 'Black bin');
      expect(provider.savedCollections.single.dates, ['2026-09-10', '2026-09-24']);
      expect(provider.savedByDate, hasLength(1));
      expect(provider.savedByDate.single.date, '2026-09-10');
      expect(provider.savedCalendarUrl, 'https://whenisbins.com/100023336956.ics');
      expect(provider.savedRetrievedAt, '2026-09-07T09:00:01Z');

      // A fresh provider (cold start) reads the same values back.
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.hasSavedSchedule, isTrue);
      expect(reloaded.savedPropertyId, 'p:4c5ee6c2f2c7c959');
      expect(reloaded.savedAddressMatch, 'exact');
      expect(reloaded.savedCollections.single.name, 'Black bin');
      expect(reloaded.savedByDate.single.date, '2026-09-10');
      expect(reloaded.savedCalendarUrl, 'https://whenisbins.com/100023336956.ics');
      expect(reloaded.savedRetrievedAt, '2026-09-07T09:00:01Z');
    });

    test('rebuilds a Schedule from the persisted data', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await SettingsProvider(prefs).saveSchedule(buildSchedule());

      final restored = SettingsProvider(prefs).savedSchedule;

      expect(restored, isNotNull);
      expect(restored!.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(restored.addressMatch, 'exact');
      expect(restored.collections.single.name, 'Black bin');
      expect(restored.collections.single.dates, ['2026-09-10', '2026-09-24']);
      expect(restored.byDate.single.weekday, 'Thursday');
      expect(restored.byDate.single.collections.single.name, 'Black bin');
      expect(restored.calendarUrl, 'https://whenisbins.com/100023336956.ics');
      expect(restored.retrievedAt, '2026-09-07T09:00:01Z');
    });

    test('notifies listeners when a schedule is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final provider =
          SettingsProvider(await SharedPreferences.getInstance());
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.saveSchedule(buildSchedule());

      expect(notifications, 1);
    });

    test('ignores a corrupt persisted schedule', () async {
      SharedPreferences.setMockInitialValues({
        'saved_schedule': 'not-json{',
      });

      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.hasSavedSchedule, isFalse);
      expect(provider.savedSchedule, isNull);
      expect(provider.savedCollections, isEmpty);
    });

    test('persists the provisional flag so a cold start never reminds from '
        'unconfirmed dates', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.saveSchedule(provisionalSchedule());

      expect(provider.savedSchedule, isNotNull);
      expect(provider.savedSchedule!.provisional, isTrue);
      // The flag survives the round-trip through storage.
      expect(SettingsProvider(prefs).savedSchedule!.provisional, isTrue);
    });

    test('a confirmed schedule is not marked provisional', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await SettingsProvider(prefs).saveSchedule(buildSchedule());

      expect(SettingsProvider(prefs).savedSchedule!.provisional, isFalse);
    });

    test('clearing the saved address clears the saved schedule', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveAddress(
        address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
        postcode: 'CB4 2HX',
        propertyId: 'p:4c5ee6c2f2c7c959',
      );
      await provider.saveSchedule(buildSchedule());

      await provider.clearSavedAddress();

      expect(provider.hasSavedSchedule, isFalse);
      expect(provider.savedSchedule, isNull);
      expect(provider.savedCollections, isEmpty);
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.hasSavedSchedule, isFalse);
      expect(reloaded.savedAddress, isNull);
    });
  });

  group('SettingsProvider schedule etag', () {
    test('has no etag by default', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.savedScheduleEtag, isNull);
    });

    test('persists the etag with the schedule across a cold start', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await SettingsProvider(prefs).saveSchedule(
        buildSchedule(),
        etag: '"v1-abc123"',
      );

      expect(SettingsProvider(prefs).savedScheduleEtag, '"v1-abc123"');
    });

    test('a schedule saved without an etag keeps the stored one', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveSchedule(buildSchedule(), etag: '"v1-abc123"');

      // The same property looked up again: its etag is still the current one.
      await provider.saveSchedule(buildSchedule());

      expect(provider.savedScheduleEtag, '"v1-abc123"');
    });

    test('saving the same address again keeps the etag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveSchedule(buildSchedule(), etag: '"v1-abc123"');

      await provider.saveAddress(
        address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
        postcode: 'CB4 2HX',
        propertyId: 'p:4c5ee6c2f2c7c959',
      );

      expect(provider.savedScheduleEtag, '"v1-abc123"');
    });

    test('switching to another address drops a stale etag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveSchedule(buildSchedule(), etag: '"v1-abc123"');

      await provider.saveAddress(
        address: '1 OTHER ROAD, CAMBRIDGE, CB1 1AA',
        postcode: 'CB1 1AA',
        propertyId: 'p:other',
      );

      expect(provider.savedScheduleEtag, isNull);
      expect(SettingsProvider(prefs).savedScheduleEtag, isNull);
    });

    test('a schedule for a different property drops a stale etag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveSchedule(buildSchedule(), etag: '"v1-abc123"');

      await provider.saveSchedule(const Schedule(
        propertyId: 'p:other',
        addressMatch: 'exact',
      ));

      expect(provider.savedScheduleEtag, isNull);
    });

    test('clearing the saved address clears the etag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveSchedule(buildSchedule(), etag: '"v1-abc123"');

      await provider.clearSavedAddress();

      expect(provider.savedScheduleEtag, isNull);
      expect(SettingsProvider(prefs).savedScheduleEtag, isNull);
    });
  });
}

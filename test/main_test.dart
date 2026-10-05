import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/main.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';
import 'package:when_is_bin_app/screens/schedule_screen.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';
import 'package:when_is_bin_app/services/schedule_recheck_service.dart';
import 'package:when_is_bin_app/services/schedule_refresh_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import 'fakes/fake_api.dart';
import 'fakes/fake_notification_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A collection three days out, so the persisted schedule always has an
  // upcoming date no matter when the suite runs.
  final nextCollection = DateTime.now().add(const Duration(days: 3));
  final nextCollectionIso = DateFormat('yyyy-MM-dd').format(nextCollection);
  final nextCollectionLabel = DateFormat('EEEE d MMMM yyyy').format(
    DateTime.parse(nextCollectionIso),
  );

  String savedScheduleJson({
    String bin = 'Black bin',
    DateTime? on,
  }) {
    final date = on ?? nextCollection;
    final iso = DateFormat('yyyy-MM-dd').format(date);
    return jsonEncode({
      'property_id': 'p:4c5ee6c2f2c7c959',
      'address_match': 'exact',
      'collections': [
        {
          'name': bin,
          'waste_type': 'refuse',
          'dates': [iso],
        },
      ],
      'by_date': [
        {
          'date': iso,
          'weekday': DateFormat('EEEE').format(date),
          'collections': [
            {'name': bin, 'waste_type': 'refuse'},
          ],
        },
      ],
      'calendar_url': 'https://whenisbins.com/100023336956.ics',
      'retrieved_at': '2026-09-07T09:00:01Z',
    });
  }

  Future<Widget> app({
    Map<String, Object>? prefs,
    ReminderSyncService? reminderSync,
    FakeWhenIsBinsApi? api,
  }) async {
    SharedPreferences.setMockInitialValues(prefs ?? {});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final sync =
        reminderSync ??
        ReminderSyncService(notifications: FakeNotificationScheduler());
    final fakeApi = api ?? FakeWhenIsBinsApi();
    return MultiProvider(
      providers: [
        Provider<ReminderSyncService>.value(value: sync),
        Provider<ScheduleRecheckService>.value(
          value: ScheduleRecheckService(
            refresh: ScheduleRefreshService(api: fakeApi),
            reminderSync: sync,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => LookupProvider(api: fakeApi),
        ),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const WhenIsBinApp(),
    );
  }

  ThemeData themeOf(WidgetTester tester, Type screenType) =>
      Theme.of(tester.element(find.byType(screenType)));

  group('WhenIsBinApp routing', () {
    testWidgets('carries the app\u2019s name as its title', (tester) async {
      await tester.pumpWidget(await app());
      await tester.pump();

      // The task switcher and accessibility services read this title.
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, 'When Is Bins');
    });

    testWidgets('shows onboarding when not onboarded', (tester) async {
      await tester.pumpWidget(await app());
      await tester.pump();

      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Find your bin day'), findsOneWidget);
    });

    testWidgets(
      'shows the schedule screen when onboarded with a saved address',
      (tester) async {
        await tester.pumpWidget(
          await app(
            prefs: {
              'onboarded': true,
              'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
              'saved_postcode': 'CB4 2HX',
              'saved_property_id': 'p:4c5ee6c2f2c7c959',
              'saved_schedule': savedScheduleJson(),
            },
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(ScheduleScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.text('Find your bin day'), findsNothing);
        // "Your bin days" appears in both the AppBar title and the body
        // headline, so assert the schedule content instead.
        expect(find.text(nextCollectionLabel), findsOneWidget);
      },
    );

    testWidgets(
      'shows the home screen when onboarded but the saved address was cleared',
      (tester) async {
        await tester.pumpWidget(
          await app(prefs: {'onboarded': true}),
        );
        await tester.pump();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(ScheduleScreen), findsNothing);
        expect(find.text('Find your bin day'), findsOneWidget);
      },
    );
  });

  group('reminders follow the app back to the foreground', () {
    // iOS drops reminders scheduled before the user has answered the
    // notification prompt, and onboarding stops waiting for that answer after
    // a few seconds. Returning to the foreground (which is also what answering
    // the prompt does) must put the reminders back.
    testWidgets(
      'reschedules reminders iOS dropped while the permission prompt was open',
      (tester) async {
        final notifications = FakeNotificationScheduler()..authorised = false;
        final reminderSync = ReminderSyncService(notifications: notifications);
        await tester.pumpWidget(
          await app(
            reminderSync: reminderSync,
            prefs: {
              'onboarded': true,
              'reminders_enabled': true,
              'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
              'saved_postcode': 'CB4 2HX',
              'saved_property_id': 'p:4c5ee6c2f2c7c959',
              'saved_schedule': savedScheduleJson(),
            },
          ),
        );
        await tester.pump();

        // Onboarding schedules while the prompt is still up: iOS keeps none.
        final settings = tester
            .element(find.byType(ScheduleScreen))
            .read<SettingsProvider>();
        await reminderSync.sync(
          schedule: settings.savedSchedule,
          enabled: true,
          reminderTime: settings.reminderTime,
        );
        expect(notifications.pending, isEmpty);

        // The user taps Allow; the prompt closing hands focus back to the app.
        notifications.authorised = true;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(notifications.pending, hasLength(1));
        expect(notifications.pending.single.binNames, ['Black bin']);
      },
    );

    testWidgets('clears reminders on resume when they are switched off', (
      tester,
    ) async {
      final notifications = FakeNotificationScheduler()..pending = const [];
      await tester.pumpWidget(
        await app(
          reminderSync: ReminderSyncService(notifications: notifications),
          prefs: {
            'onboarded': true,
            'reminders_enabled': false,
            'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
            'saved_postcode': 'CB4 2HX',
            'saved_property_id': 'p:4c5ee6c2f2c7c959',
            'saved_schedule': savedScheduleJson(),
          },
        ),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(notifications.scheduled, isEmpty);
      expect(notifications.cancelAllCalls, 1);
    });
  });

  group('the schedule is re-checked when the app comes back', () {
    final laterCollection = DateTime.now().add(const Duration(days: 5));
    final laterLabel = DateFormat('EEEE d MMMM yyyy').format(
      DateTime.parse(DateFormat('yyyy-MM-dd').format(laterCollection)),
    );

    Map<String, Object> savedPrefs({required Duration checkedAgo}) => {
          'onboarded': true,
          'reminders_enabled': true,
          'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
          'saved_postcode': 'CB4 2HX',
          'saved_property_id': 'p:4c5ee6c2f2c7c959',
          'saved_schedule': savedScheduleJson(),
          'saved_schedule_etag': '"v1"',
          'schedule_checked_at':
              DateTime.now().toUtc().subtract(checkedAgo).toIso8601String(),
        };

    void resume(WidgetTester tester) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    testWidgets(
      'picks up what the background task saved before re-syncing reminders',
      (tester) async {
        // The background task writes the moved schedule from its own isolate,
        // so this isolate's cached copy is stale. Re-syncing from the cache on
        // resume would put the old dates' reminders back.
        final notifications = FakeNotificationScheduler();
        final prefs = savedPrefs(checkedAgo: const Duration(hours: 1));
        await tester.pumpWidget(
          await app(
            prefs: prefs,
            reminderSync: ReminderSyncService(notifications: notifications),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text(nextCollectionLabel), findsOneWidget);

        // What the background isolate leaves in storage.
        SharedPreferences.setMockInitialValues({
          ...prefs,
          'saved_schedule': savedScheduleJson(
            bin: 'Blue bin',
            on: laterCollection,
          ),
          'saved_schedule_etag': '"v2"',
          'schedule_checked_at': DateTime.now().toUtc().toIso8601String(),
        });

        resume(tester);
        await tester.pump();
        await tester.pump();

        expect(notifications.pending.single.binNames, ['Blue bin']);
        expect(find.text(laterLabel), findsOneWidget);
        expect(find.text(nextCollectionLabel), findsNothing);
      },
    );

    testWidgets('does not ask the API again within the recheck interval', (
      tester,
    ) async {
      final api = FakeWhenIsBinsApi();
      await tester.pumpWidget(
        await app(
          api: api,
          prefs: savedPrefs(checkedAgo: const Duration(hours: 1)),
        ),
      );
      await tester.pump();

      resume(tester);
      await tester.pump();
      await tester.pump();

      expect(api.scheduleCheckCalls, 0);
    });

    testWidgets('re-checks a stale schedule and shows the moved date', (
      tester,
    ) async {
      final notifications = FakeNotificationScheduler();
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = ScheduleCheck.updated(
          Schedule(
            propertyId: 'p:4c5ee6c2f2c7c959',
            addressMatch: 'exact',
            collections: [
              Collection(
                name: 'Black bin',
                wasteType: 'refuse',
                dates: [DateFormat('yyyy-MM-dd').format(laterCollection)],
              ),
            ],
            byDate: [
              ByDateEntry(
                date: DateFormat('yyyy-MM-dd').format(laterCollection),
                weekday: DateFormat('EEEE').format(laterCollection),
                collections: const [
                  ByDateCollection(name: 'Black bin', wasteType: 'refuse'),
                ],
              ),
            ],
          ),
          etag: '"v2"',
        );
      await tester.pumpWidget(
        await app(
          api: api,
          reminderSync: ReminderSyncService(notifications: notifications),
          prefs: savedPrefs(checkedAgo: const Duration(hours: 13)),
        ),
      );
      await tester.pump();
      await tester.pump();

      resume(tester);
      await tester.pump();
      await tester.pump();

      expect(api.scheduleCheckCalls, 1);
      expect(api.lastScheduleEtag, '"v1"');
      expect(find.text(laterLabel), findsOneWidget);
      expect(
        notifications.pending.single.fireAt.day,
        laterCollection.subtract(const Duration(days: 1)).day,
      );
    });
  });

  group('reminders follow the saved address and time', () {
    final savedPrefs = <String, Object>{
      'onboarded': true,
      'reminders_enabled': true,
      'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      'saved_postcode': 'CB4 2HX',
      'saved_property_id': 'p:4c5ee6c2f2c7c959',
      'saved_schedule': savedScheduleJson(),
    };

    final newSchedule = Schedule(
      propertyId: 'p:new-home',
      addressMatch: 'exact',
      collections: [
        Collection(
          name: 'Blue bin',
          wasteType: 'recycling',
          dates: [nextCollectionIso],
        ),
      ],
    );

    /// Pumps the app with its launch-time reminders already on the device.
    Future<(FakeNotificationScheduler, SettingsProvider)> pumpApp(
      WidgetTester tester, {
      Map<String, Object>? prefs,
    }) async {
      final notifications = FakeNotificationScheduler();
      final reminderSync = ReminderSyncService(notifications: notifications);
      await tester.pumpWidget(
        await app(prefs: prefs ?? savedPrefs, reminderSync: reminderSync),
      );
      await tester.pump();
      final settings = tester
          .element(find.byType(WhenIsBinApp))
          .read<SettingsProvider>();
      await reminderSync.sync(
        schedule: settings.savedSchedule,
        enabled: settings.remindersEnabled,
        reminderTime: settings.reminderTime,
      );
      return (notifications, settings);
    }

    testWidgets('removing the saved address cancels its reminders', (
      tester,
    ) async {
      final (notifications, settings) = await pumpApp(tester);
      expect(notifications.pending, hasLength(1));

      await settings.clearSavedAddress();
      await tester.pump();

      expect(notifications.pending, isEmpty);
    });

    testWidgets('a new address after removing the old one gets reminders', (
      tester,
    ) async {
      final (notifications, settings) = await pumpApp(tester);
      await settings.clearSavedAddress();
      await tester.pump();

      // What the address screens do once a lookup resolves.
      await settings.saveAddress(
        address: '1 NEW ROAD, CAMBRIDGE, CB1 1AA',
        postcode: 'CB1 1AA',
        propertyId: 'p:new-home',
      );
      await settings.saveSchedule(newSchedule);
      await tester.pump();

      expect(notifications.pending, hasLength(1));
      expect(notifications.pending.single.binNames, ['Blue bin']);
    });

    testWidgets('a new address gets no reminders while they are off', (
      tester,
    ) async {
      final (notifications, settings) = await pumpApp(
        tester,
        prefs: {...savedPrefs, 'reminders_enabled': false},
      );

      await settings.saveSchedule(newSchedule);
      await tester.pump();

      expect(notifications.pending, isEmpty);
    });

    testWidgets('changing the reminder time moves the reminders', (
      tester,
    ) async {
      final (notifications, settings) = await pumpApp(tester);
      expect(notifications.pending.single.fireAt.hour, 19);

      await settings.setReminderTime(ReminderTime.morning);
      await tester.pump();

      expect(notifications.pending.single.fireAt.hour, 9);
    });
  });

  group('stays light whatever the device theme', () {
    // The app mirrors the whenisbins.com design system, which is light. A phone
    // in dark mode must not flip the app into the dark theme — the onboarding
    // flow already forces light, and every other route has to match it.
    testWidgets(
      'the search screen stays light on a dark-mode phone',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.dark;
        addTearDown(
          tester.platformDispatcher.clearPlatformBrightnessTestValue,
        );

        await tester.pumpWidget(await app(prefs: {'onboarded': true}));
        await tester.pump();

        expect(
          themeOf(tester, HomeScreen).brightness,
          Brightness.light,
        );
        expect(
          themeOf(tester, HomeScreen).scaffoldBackgroundColor,
          AppColors.paper,
        );
      },
    );

    testWidgets(
      'the bin-days screen stays light on a dark-mode phone',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.dark;
        addTearDown(
          tester.platformDispatcher.clearPlatformBrightnessTestValue,
        );

        await tester.pumpWidget(
          await app(
            prefs: {
              'onboarded': true,
              'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
              'saved_postcode': 'CB4 2HX',
              'saved_property_id': 'p:4c5ee6c2f2c7c959',
              'saved_schedule': savedScheduleJson(),
            },
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(ScheduleScreen), findsOneWidget);
        final theme = themeOf(tester, ScheduleScreen);
        expect(theme.brightness, Brightness.light);
        expect(theme.scaffoldBackgroundColor, AppColors.paper);
        // Light ink on light paper — not the dark theme's inkLight.
        expect(theme.textTheme.headlineLarge?.color, AppColors.ink);
      },
    );

    testWidgets(
      'and stays light on a light-mode phone',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(
          tester.platformDispatcher.clearPlatformBrightnessTestValue,
        );

        await tester.pumpWidget(await app(prefs: {'onboarded': true}));
        await tester.pump();

        expect(
          themeOf(tester, HomeScreen).brightness,
          Brightness.light,
        );
        expect(
          themeOf(tester, HomeScreen).scaffoldBackgroundColor,
          AppColors.paper,
        );
      },
    );
  });
}

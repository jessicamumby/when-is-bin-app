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

  String savedScheduleJson() {
    return jsonEncode({
      'property_id': 'p:4c5ee6c2f2c7c959',
      'address_match': 'exact',
      'collections': [
        {
          'name': 'Black bin',
          'waste_type': 'refuse',
          'dates': [nextCollectionIso],
        },
      ],
      'by_date': [
        {
          'date': nextCollectionIso,
          'weekday': DateFormat('EEEE').format(nextCollection),
          'collections': [
            {'name': 'Black bin', 'waste_type': 'refuse'},
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
  }) async {
    SharedPreferences.setMockInitialValues(prefs ?? {});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    return MultiProvider(
      providers: [
        Provider<ReminderSyncService>.value(
          value:
              reminderSync ??
              ReminderSyncService(notifications: FakeNotificationScheduler()),
        ),
        ChangeNotifierProvider(
          create: (_) => LookupProvider(api: FakeWhenIsBinsApi()),
        ),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const WhenIsBinApp(),
    );
  }

  ThemeData themeOf(WidgetTester tester, Type screenType) =>
      Theme.of(tester.element(find.byType(screenType)));

  group('WhenIsBinApp routing', () {
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

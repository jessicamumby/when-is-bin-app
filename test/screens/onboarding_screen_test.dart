import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/main.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/onboarding_screen.dart';
import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';

import '../fakes/fake_api.dart';
import '../fakes/fake_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const postcode = 'CB4 2HX';

  final candidate = AddressCandidate(id: 'c1', label: '15 EXAMPLE COURT');
  final schedule = Schedule(
    propertyId: 'p:1',
    addressMatch: 'exact',
    collections: [
      Collection(name: 'Black bin', wasteType: 'rubbish', dates: ['2026-10-01']),
    ],
  );

  Future<SettingsProvider> makeSettings({bool onboarded = false}) async {
    SharedPreferences.setMockInitialValues({'onboarded': onboarded});
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  Widget buildApp(
    LookupProvider lookup,
    SettingsProvider settings,
    FakeNotificationService notifications,
  ) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LookupProvider>.value(value: lookup),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<NotificationService>.value(value: notifications),
                Provider<ReminderSyncService>.value(
                  value: ReminderSyncService(notifications: notifications),
                ),
              ],
              child: const MaterialApp(home: OnboardingScreen()),
            );
  }

  group('Onboarding postcode step', () {
    testWidgets('shows the postcode entry form', (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi();
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      expect(find.text('Find your bin day'), findsOneWidget);
      expect(find.text('Postcode'), findsOneWidget);
      expect(find.text('Find my bin day'), findsOneWidget);
    });

    testWidgets('validates an empty postcode', (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi();
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      await tester.tap(find.text('Find my bin day'));
      await tester.pump();

      expect(find.text('Enter a postcode.'), findsOneWidget);
    });

    testWidgets('submits a postcode and opens the address select screen',
        (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: postcode,
          requiredInput: 'none',
          candidates: [candidate],
        );
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      expect(find.text('15 EXAMPLE COURT'), findsOneWidget);
    });

    testWidgets('pushes a light address select screen under a dark app theme',
        (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: postcode,
          requiredInput: 'none',
          candidates: [candidate],
        );
      final lookup = LookupProvider(api: api);
      final notifications = FakeNotificationService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LookupProvider>.value(value: lookup),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            Provider<NotificationService>.value(value: notifications),
            Provider<ReminderSyncService>.value(
              value: ReminderSyncService(notifications: notifications),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const OnboardingScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      final context = tester.element(find.text('15 EXAMPLE COURT'));
      expect(Theme.of(context).brightness, Brightness.light);

      // The body headline must use the light ink (readable on white), not the
      // dark theme's light-grey inkLight.
      final headline = tester
          .widgetList<Text>(find.text('Select your address'))
          .firstWhere((t) => t.style?.fontSize == 40);
      expect(headline.style?.color, AppColors.ink);
    });
  });

  group('Onboarding reminder step', () {
    Future<LookupProvider> lookupWithSchedule() async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(id: 'L1', status: 'done', result: schedule),
        ];
      final lookup = LookupProvider(api: api);
      await lookup.selectAddress(candidate, postcode: postcode);
      return lookup;
    }

    testWidgets('asks for a reminder time once a schedule is found',
        (tester) async {
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      expect(find.text('When should we remind you?'), findsOneWidget);
      expect(find.text('Morning before (9:00am)'), findsOneWidget);
      expect(find.text('Evening before (7:00pm)'), findsOneWidget);
      expect(find.text('Turn on reminders'), findsOneWidget);
    });

    testWidgets(
        'turning on reminders saves the time, requests permission, '
        'and marks onboarding complete', (tester) async {
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService();

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Morning before (9:00am)'));
      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      expect(settings.reminderTime, ReminderTime.morning);
      expect(settings.isOnboarded, isTrue);
      expect(notifications.requestPermissionCount, 1);
    });

    testWidgets('turning on reminders schedules the collections',
        (tester) async {
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService();

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      expect(notifications.scheduleCount, 1);
      expect(notifications.lastReminders, isNotEmpty);
    });
  });

  group('Onboarding gating', () {
    Widget buildAppRoot(
      LookupProvider lookup,
      SettingsProvider settings,
      FakeNotificationService notifications,
    ) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LookupProvider>.value(value: lookup),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<NotificationService>.value(value: notifications),
                    Provider<ReminderSyncService>.value(
                      value: ReminderSyncService(notifications: notifications),
                    ),
                  ],
                  child: const WhenIsBinApp(),
                );
    }

    testWidgets('shows onboarding until the user has completed it',
        (tester) async {
      final settings = await makeSettings(onboarded: false);
      final lookup = LookupProvider(api: FakeWhenIsBinsApi());

      await tester.pumpWidget(
        buildAppRoot(lookup, settings, FakeNotificationService()),
      );
      await tester.pumpAndSettle();

      // Onboarding is shown, not the home screen.
      expect(find.text('Use this service to:'), findsNothing);

      await settings.markOnboarded();
      await tester.pumpAndSettle();

      // The home screen replaces onboarding.
      expect(find.text('Use this service to:'), findsOneWidget);
    });

    testWidgets('goes straight to home when already onboarded',
        (tester) async {
      final settings = await makeSettings(onboarded: true);
      final lookup = LookupProvider(api: FakeWhenIsBinsApi());

      await tester.pumpWidget(
        buildAppRoot(lookup, settings, FakeNotificationService()),
      );
      await tester.pumpAndSettle();

      // Straight to the home screen, no onboarding prompt.
      expect(find.text('Use this service to:'), findsOneWidget);
      expect(find.text('Turn on reminders'), findsNothing);
    });
  });

  group('Onboarding theme', () {
    testWidgets('renders in light mode even under a dark app theme',
        (tester) async {
      final settings = await makeSettings();
      final lookup = LookupProvider(api: FakeWhenIsBinsApi());
      final notifications = FakeNotificationService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<LookupProvider>.value(value: lookup),
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              Provider<NotificationService>.value(value: notifications),
              Provider<ReminderSyncService>.value(
                value: ReminderSyncService(notifications: notifications),
              ),
            ],
            child: const OnboardingScreen(),
          ),
        ),
      );

      final context = tester.element(find.text('Find your bin day'));
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        AppColors.paper,
      );
    });
  });
}
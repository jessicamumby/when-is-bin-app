import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

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
      Collection(
        name: 'Black bin',
        wasteType: 'rubbish',
        // Always a week out: a fixed date eventually passes and leaves
        // nothing to remind about.
        dates: [
          DateFormat('yyyy-MM-dd')
              .format(DateTime.now().add(const Duration(days: 7))),
        ],
      ),
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

    testWidgets('promises a reminder the morning or evening before', (
      tester,
    ) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi();
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      expect(
        find.text(
          'Enter your postcode to find which bins go out, and when. '
          'Get a reminder the morning or evening before.',
        ),
        findsOneWidget,
      );
      // Reminders are offered at 9:00am or 7:00pm on the day before, so the
      // old "night before" promise was narrower than what the app does.
      expect(find.textContaining('the night before'), findsNothing);
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

    testWidgets('submits a postcode and opens the address select screen', (
      tester,
    ) async {
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

    testWidgets('pushes a light address select screen under a dark app theme', (
      tester,
    ) async {
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

    testWidgets('shows the reminder step after choosing an address', (
      tester,
    ) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: postcode,
          requiredInput: 'none',
          candidates: [candidate],
        )
        ..lookupResponses = [
          Lookup(id: 'L1', status: 'done', result: schedule),
        ];
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
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      // On the address select screen, pick the address.
      await tester.tap(find.text('15 EXAMPLE COURT'));
      await tester.pumpAndSettle();

      // Back on onboarding, the reminder step is shown.
      expect(find.text('When should we remind you?'), findsOneWidget);
      expect(find.text('Turn on reminders'), findsOneWidget);
    });
  });

  group('Onboarding without a candidate list', () {
    // Cambridge answers CB4 2HX with no address list: the postcode alone
    // identifies the collection round. Onboarding used to dead-end here.
    final postcodeOnly = AddressLookup(
      postcode: postcode,
      requiredInput: 'none',
      council: const Council(id: 'E07000008', name: 'Cambridge City Council'),
    );
    const deadEnd =
        'This council needs more information. Please try again later.';

    testWidgets('a postcode-only council completes onboarding and lands on '
        'the bin days', (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..addressLookup = postcodeOnly
        ..lookupResponses = [
          Lookup(id: 'L1', status: 'done', result: schedule),
        ];
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
          child: const WhenIsBinApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      // The same form the home screen opens, not a dead end.
      expect(find.text(deadEnd), findsNothing);
      expect(find.text('A few more details'), findsOneWidget);

      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      // The postcode alone was submitted, and the address and schedule kept.
      expect(api.lastLookupBody, {'postcode': postcode});
      expect(settings.savedAddress, postcode);
      expect(settings.hasSavedSchedule, isTrue);

      // Back on onboarding, at the reminder step.
      expect(find.text('When should we remind you?'), findsOneWidget);

      await tester.tap(find.text('Turn on reminders'));
      await tester.pumpAndSettle();

      expect(settings.isOnboarded, isTrue);
      expect(settings.remindersEnabled, isTrue);
      expect(notifications.scheduleCount, greaterThanOrEqualTo(1));
      expect(notifications.lastReminders, isNotEmpty);

      // Onboarding hands over to the saved bin days, with no form left
      // stacked on top.
      expect(find.text('Your bin days'), findsWidgets);
      expect(find.text('A few more details'), findsNothing);
      expect(find.text('Turn on reminders'), findsNothing);
    });

    testWidgets('a council that needs the first line opens a light address '
        'form under a dark app theme', (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: postcode,
          requiredInput: 'property',
          council: const Council(
            id: 'E07000008',
            name: 'Cambridge City Council',
          ),
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

      expect(find.text(deadEnd), findsNothing);
      expect(find.text('First line of your address'), findsOneWidget);
      final context = tester.element(find.text('A few more details'));
      expect(Theme.of(context).brightness, Brightness.light);
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

    testWidgets('asks for a reminder time once a schedule is found', (
      tester,
    ) async {
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

    testWidgets('turning on reminders saves the time, requests permission, '
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

    testWidgets('turning on reminders schedules the collections', (
      tester,
    ) async {
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService();

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      expect(notifications.scheduleCount, 1);
      expect(notifications.lastReminders, isNotEmpty);
    });

    testWidgets('completes onboarding even when the permission dialog never '
        'returns a verdict', (tester) async {
      // The orphaned Android permission callback: the OS box appears, the
      // user taps Allow or Don't allow, but the plugin's onRequestPermissions
      // result never reaches the waiting Dart future, so `await` never
      // completes. The app must not strand the user on onboarding forever.
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService()
        ..hangPermissionRequest = true;

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      // A real permission dialog would resolve well inside this budget; a hung
      // one must not block the user from progressing.
      await tester.pump(const Duration(seconds: 10));

      expect(settings.isOnboarded, isTrue);
    });

    testWidgets(
      'completes onboarding even when scheduling the reminders fails',
      (tester) async {
        // The plugin's zonedSchedule can error (or hang) — e.g. when its
        // extractNotificationDetails returns null and the method-channel result
        // is never delivered. A scheduling failure must not strand the user on
        // onboarding; they can re-enable reminders from Settings later.
        final settings = await makeSettings();
        final lookup = await lookupWithSchedule();
        final notifications = FakeNotificationService()..throwOnSchedule = true;

        await tester.pumpWidget(buildApp(lookup, settings, notifications));

        await tester.tap(find.text('Turn on reminders'));
        await tester.pump();

        expect(settings.isOnboarded, isTrue);
      },
    );

    testWidgets('completes onboarding without waiting for reminders to be '
        'scheduled', (tester) async {
      // In the release build the plugin's zonedSchedule failed on the platform
      // side; a scheduling call that stalls must not keep the user on
      // onboarding, even for the length of the sync timeout.
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService()..hangSchedule = true;

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      expect(notifications.scheduleCount, 1);
      expect(settings.isOnboarded, isTrue);

      // Let the bounded sync time out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('shows progress and ignores repeat taps while the permission '
        'dialog is open', (tester) async {
      final settings = await makeSettings();
      final lookup = await lookupWithSchedule();
      final notifications = FakeNotificationService()
        ..hangPermissionRequest = true;

      await tester.pumpWidget(buildApp(lookup, settings, notifications));

      await tester.tap(find.text('Turn on reminders'));
      await tester.pump();

      expect(find.text('Turn on reminders'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(notifications.requestPermissionCount, 1);

      await tester.pump(const Duration(seconds: 10));
      expect(settings.isOnboarded, isTrue);
    });
  });

  group('Onboarding rate limited', () {
    testWidgets('reads as a busy service, never as the API allowance',
        (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 429,
          problem: 'rate_limited',
          detail: 'Network address allowance exceeded for wait token.',
        );
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Lots of people are checking bin days right now. '
          'Try again in a minute.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('allowance'), findsNothing);
    });

    testWidgets('shows the Retry-After as a countdown', (tester) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 429,
          problem: 'rate_limited',
          detail: 'Slow down.',
          retryAfter: Duration(seconds: 5),
        );
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      expect(find.text('Try again in about 5 seconds'), findsOneWidget);
    });
  });

  group('Onboarding offline', () {
    testWidgets('says the phone is offline, never the system error', (
      tester,
    ) async {
      final settings = await makeSettings();
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 0,
          problem: WhenIsBinsApi.networkProblem,
          detail: "Failed host lookup: 'whenisbins.com'",
        );
      final lookup = LookupProvider(api: api);

      await tester.pumpWidget(
        buildApp(lookup, settings, FakeNotificationService()),
      );

      await tester.enterText(find.byType(TextField), postcode);
      await tester.tap(find.text('Find my bin day'));
      await tester.pumpAndSettle();

      expect(
        find.text('You\u2019re offline. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed host lookup'), findsNothing);
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

    testWidgets('shows onboarding until the user has completed it', (
      tester,
    ) async {
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

    testWidgets('goes straight to home when already onboarded', (tester) async {
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
    testWidgets('renders in light mode even under a dark app theme', (
      tester,
    ) async {
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
      expect(Theme.of(context).scaffoldBackgroundColor, AppColors.paper);
    });
  });
}

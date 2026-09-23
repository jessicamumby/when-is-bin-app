import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/schedule_screen.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../fakes/fake_api.dart';
import '../fakes/fake_notification_scheduler.dart';

/// A fake whose lookup never settles, so "loading" is a real state to observe
/// rather than one the test races through.
class _PendingLookupApi extends FakeWhenIsBinsApi {
  final _pending = Completer<Lookup>();

  @override
  Future<Lookup> createLookup(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) {
    createLookupCalls++;
    lookupBodies.add(body);
    return _pending.future;
  }

  void settle(Schedule result) {
    if (!_pending.isCompleted) {
      _pending.complete(
        Lookup(id: 'lookup-1', status: 'done', result: result),
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A collection three days out, so there is always something to remind about.
  final nextCollection = DateTime.now().add(const Duration(days: 3));
  final nextCollectionIso = DateFormat('yyyy-MM-dd').format(nextCollection);
  final nextCollectionLabel = DateFormat('EEEE d MMMM yyyy').format(
    DateTime.parse(nextCollectionIso),
  );

  Schedule schedule({
    bool provisional = false,
    String? dateConfidence,
    String? dateCompleteness,
  }) {
    return Schedule(
      propertyId: 'p:4c5ee6c2f2c7c959',
      addressMatch: 'exact',
      provisional: provisional,
      dateConfidence: dateConfidence,
      dateCompleteness: dateCompleteness,
      collections: [
        Collection(
          name: 'Black bin',
          wasteType: 'refuse',
          dates: [nextCollectionIso],
        ),
      ],
      byDate: [
        ByDateEntry(
          date: nextCollectionIso,
          weekday: DateFormat('EEEE').format(nextCollection),
          collections: const [
            ByDateCollection(name: 'Black bin', wasteType: 'refuse'),
          ],
        ),
      ],
    );
  }

  Future<SettingsProvider> makeSettings({bool remindersEnabled = false}) async {
    SharedPreferences.setMockInitialValues({
      'reminders_enabled': remindersEnabled,
    });
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  ReminderSyncService sync() => ReminderSyncService(
        notifications: FakeNotificationScheduler(),
        now: DateTime.now,
      );

  Widget buildApp(SettingsProvider settings, ReminderSyncService sync) {
    final lookup = LookupProvider(api: FakeWhenIsBinsApi())
      ..restoreSchedule(schedule());
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
        Provider<ReminderSyncService>.value(value: sync),
      ],
      child: const MaterialApp(home: ScheduleScreen()),
    );
  }

  /// The schedule screen over a given lookup, with the tokens of [theme].
  Widget scheduleApp(
    LookupProvider lookup,
    SettingsProvider settings, {
    ThemeData? theme,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
        Provider<ReminderSyncService>.value(value: sync()),
      ],
      child: MaterialApp(theme: theme, home: const ScheduleScreen()),
    );
  }

  /// The screen showing [forSchedule], for the states that are about the data
  /// rather than the journey that fetched it.
  Widget buildScheduleApp(
    SettingsProvider settings,
    Schedule forSchedule, {
    ThemeData? theme,
  }) {
    final lookup = LookupProvider(api: FakeWhenIsBinsApi())
      ..restoreSchedule(forSchedule);
    return scheduleApp(lookup, settings, theme: theme);
  }

  Color? textColour(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style?.color;

  /// The fill of the nearest decorated box around [inside].
  Color? panelColour(WidgetTester tester, Finder inside) {
    final ancestors = find
        .ancestor(of: inside, matching: find.byType(Container))
        .evaluate()
        .map((element) => element.widget)
        .whereType<Container>();
    for (final container in ancestors) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        return decoration.color;
      }
    }
    return null;
  }

  /// The schedule screen pushed from a host screen, so "a way back" can be
  /// asserted by popping it rather than guessing at the route.
  Widget buildHostedSchedule(
    SettingsProvider settings,
    LookupProvider lookup,
  ) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
        Provider<ReminderSyncService>.value(value: sync()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScheduleScreen()),
                ),
                child: const Text('Open your bin days'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSchedule(WidgetTester tester) async {
    await tester.tap(find.text('Open your bin days'));
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('the switch shows the persisted reminder setting',
      (tester) async {
    final settings = await makeSettings(remindersEnabled: true);

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(
          notifications: FakeNotificationScheduler(),
          now: DateTime.now,
        ),
      ),
    );

    expect(switchValue(tester), isTrue);
    expect(find.text('Reminders on'), findsOneWidget);
  });

  testWidgets('turning reminders on schedules them and persists the switch',
      (tester) async {
    final settings = await makeSettings();
    final scheduler = FakeNotificationScheduler();

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );
    expect(switchValue(tester), isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isTrue);
    expect(settings.remindersEnabled, isTrue);
    expect(scheduler.scheduled, hasLength(1));
    expect(scheduler.scheduled.single.single.binNames, ['Black bin']);
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('keeps reminders off and warns when permission is denied',
      (tester) async {
    final settings = await makeSettings();
    final scheduler = FakeNotificationScheduler()..permissionGranted = false;

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
    expect(settings.remindersEnabled, isFalse);
    expect(scheduler.scheduled, isEmpty);
    expect(
      find.text(
        'Turn on notifications for this app in your device settings to get '
        'bin reminders.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('turning reminders off cancels them and persists the switch',
      (tester) async {
    final settings = await makeSettings(remindersEnabled: true);
    final scheduler = FakeNotificationScheduler();

    await tester.pumpWidget(
      buildApp(
        settings,
        ReminderSyncService(notifications: scheduler, now: DateTime.now),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(switchValue(tester), isFalse);
    expect(settings.remindersEnabled, isFalse);
    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.permissionRequests, 0);
  });

  testWidgets('shows an empty state with a way back when nothing is loaded',
      (tester) async {
    final settings = await makeSettings();
    final lookup = LookupProvider(api: FakeWhenIsBinsApi());

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);

    expect(find.text('No schedule yet'), findsOneWidget);
    expect(find.text('Search for your postcode'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the empty state sends the user back to the search screen',
      (tester) async {
    final settings = await makeSettings();
    final lookup = LookupProvider(api: FakeWhenIsBinsApi());

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);
    await tester.tap(find.text('Search for your postcode'));
    await tester.pumpAndSettle();

    expect(find.text('No schedule yet'), findsNothing);
    expect(find.text('Open your bin days'), findsOneWidget);
  });

  testWidgets('shows a spinner while the lookup is still running',
      (tester) async {
    final settings = await makeSettings();
    final api = _PendingLookupApi();
    final lookup = LookupProvider(api: api);
    unawaited(lookup.submitLookup(postcode: 'CB4 2HX', address: const {}));

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await tester.tap(find.text('Open your bin days'));
    // Not pumpAndSettle: the spinner never stops, so the transition is pumped
    // by hand instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Finding your bin days\u2026'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No schedule yet'), findsNothing);

    // …and the spinner gives way to the bin days once the lookup lands.
    api.settle(schedule());
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(nextCollectionLabel), findsOneWidget);
  });

  testWidgets('shows a friendly error with a retry when the lookup failed',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup =
          AddressLookup(postcode: 'CB4 2HX', requiredInput: 'none');
    final lookup = LookupProvider(api: api);
    await lookup.lookupPostcode('CB4 2HX');
    api.error = const ApiException(
      statusCode: 502,
      problem: 'upstream_unavailable',
      detail: 'The council website did not respond.',
    );
    await lookup.submitLookup(postcode: 'CB4 2HX', address: const {});

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);

    expect(find.text('We could not load your bin days.'), findsOneWidget);
    expect(find.text('The council website did not respond.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Search for your postcode'), findsOneWidget);
    expect(find.text('No schedule yet'), findsNothing);
  });

  testWidgets('Try again re-asks the council and clears the error',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup =
          AddressLookup(postcode: 'CB4 2HX', requiredInput: 'none');
    final lookup = LookupProvider(api: api);
    await lookup.lookupPostcode('CB4 2HX');
    api.error = const ApiException(statusCode: 502, problem: 'upstream_error');
    await lookup.submitLookup(postcode: 'CB4 2HX', address: const {});
    expect(api.addressCallCount, 1);

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);
    expect(find.text('We could not load your bin days.'), findsOneWidget);

    api.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(api.addressCallCount, 2);
    expect(find.text('We could not load your bin days.'), findsNothing);
  });

  testWidgets('an error with nothing to retry still offers a way back',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..error = const ApiException(statusCode: 502, problem: 'lookup_failed');
    final lookup = LookupProvider(api: api);
    await lookup.submitLookup(postcode: 'CB4 2HX', address: const {});

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);

    expect(find.text('We could not load your bin days.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Search for your postcode'), findsOneWidget);
  });

  group('scheduleDateCaveat', () {
    test('says the dates cover the next collection only', () {
      expect(
        scheduleDateCaveat(schedule(dateCompleteness: 'next_only')),
        'These dates cover the next collection only.',
      );
      expect(
        scheduleDateCaveat(schedule(dateConfidence: 'next_collection_only')),
        'These dates cover the next collection only.',
      );
    });

    test('says a limited horizon is a limited horizon', () {
      expect(
        scheduleDateCaveat(schedule(dateCompleteness: 'limited_horizon')),
        'Your council has only published dates for the next few weeks.',
      );
    });

    test('says a weekday-only publication is a weekday', () {
      expect(
        scheduleDateCaveat(schedule(dateCompleteness: 'weekday_only')),
        'Your council publishes the collection weekday only, so the exact '
            'date may change.',
      );
    });

    test('says a projection is a projection', () {
      expect(
        scheduleDateCaveat(schedule(dateConfidence: 'council_projection')),
        'This council has not published a full calendar, so these dates are a '
            'projection.',
      );
    });

    test('still warns about a projection when the horizon is full', () {
      expect(
        scheduleDateCaveat(
          schedule(
            dateConfidence: 'council_projection',
            dateCompleteness: 'full_horizon',
          ),
        ),
        'This council has not published a full calendar, so these dates are a '
            'projection.',
      );
    });

    test('says nothing about a published full calendar', () {
      expect(
        scheduleDateCaveat(
          schedule(
            dateConfidence: 'published_calendar',
            dateCompleteness: 'full_horizon',
          ),
        ),
        isNull,
      );
    });

    test('says nothing about values it does not know', () {
      expect(scheduleDateCaveat(schedule()), isNull);
      expect(
        scheduleDateCaveat(
          schedule(dateConfidence: 'something_new', dateCompleteness: 'other'),
        ),
        isNull,
      );
    });
  });

  testWidgets('shows the caveat for a next-collection-only schedule',
      (tester) async {
    final settings = await makeSettings();

    await tester.pumpWidget(
      buildScheduleApp(settings, schedule(dateCompleteness: 'next_only')),
    );

    expect(
      find.text('These dates cover the next collection only.'),
      findsOneWidget,
    );
    expect(find.text(nextCollectionLabel), findsOneWidget);
  });

  testWidgets('shows no caveat for a published full calendar', (tester) async {
    final settings = await makeSettings();

    await tester.pumpWidget(
      buildScheduleApp(
        settings,
        schedule(
          dateConfidence: 'published_calendar',
          dateCompleteness: 'full_horizon',
        ),
      ),
    );

    expect(
      find.text('These dates cover the next collection only.'),
      findsNothing,
    );
    expect(
      find.text(
        'This council has not published a full calendar, so these dates are a '
        'projection.',
      ),
      findsNothing,
    );
  });

  testWidgets('labels a provisional schedule as still being checked',
      (tester) async {
    final settings = await makeSettings();

    await tester.pumpWidget(
      buildScheduleApp(settings, schedule(provisional: true)),
    );

    expect(
      find.text('Provisional \u2014 your address is still being checked'),
      findsOneWidget,
    );
  });

  testWidgets('keeps reminders off a provisional schedule', (tester) async {
    final settings = await makeSettings();

    await tester.pumpWidget(
      buildScheduleApp(settings, schedule(provisional: true)),
    );

    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(
      find.text('Reminders need a confirmed address.'),
      findsOneWidget,
    );
  });

  group('dark mode', () {
    testWidgets('renders its own tokens in dark mode', (tester) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        buildScheduleApp(
          settings,
          schedule(dateCompleteness: 'next_only'),
          theme: AppTheme.dark,
        ),
      );

      expect(
        textColour(tester, find.text(nextCollectionLabel)),
        AppColors.tealDark,
      );
      expect(
        textColour(tester, find.textContaining('Collection dates come from')),
        AppColors.mutedDark,
      );
      expect(
        panelColour(tester, find.text('Put out: Black bin')),
        AppColors.softCardDark,
      );
    });

    testWidgets('keeps the light tokens in light mode', (tester) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        buildScheduleApp(
          settings,
          schedule(dateCompleteness: 'next_only'),
          theme: AppTheme.light,
        ),
      );

      expect(textColour(tester, find.text(nextCollectionLabel)), AppColors.teal);
      expect(
        textColour(tester, find.textContaining('Collection dates come from')),
        AppColors.muted,
      );
      expect(
        panelColour(tester, find.text('Put out: Black bin')),
        AppColors.softAqua,
      );
    });

    testWidgets('renders the provisional label on the dark panel',
        (tester) async {
      final settings = await makeSettings();
      final label =
          find.text('Provisional \u2014 your address is still being checked');

      await tester.pumpWidget(
        buildScheduleApp(
          settings,
          schedule(provisional: true),
          theme: AppTheme.dark,
        ),
      );

      expect(textColour(tester, label), AppColors.inkLight);
      expect(panelColour(tester, label), AppColors.softCoralDark);
    });

    testWidgets('renders the empty state in dark mode', (tester) async {
      final settings = await makeSettings();

      await tester.pumpWidget(
        scheduleApp(
          LookupProvider(api: FakeWhenIsBinsApi()),
          settings,
          theme: AppTheme.dark,
        ),
      );

      expect(
        textColour(tester, find.text('No schedule yet')),
        AppColors.inkLight,
      );
      expect(
        textColour(
          tester,
          find.text('Search for your postcode to find your bin days.'),
        ),
        AppColors.mutedDark,
      );
    });
  });
}

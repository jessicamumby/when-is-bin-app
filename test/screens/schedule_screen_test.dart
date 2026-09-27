import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A fake whose lookup is created straight away but whose wait never answers,
/// so the loading state can be inspected with the council's own figures in
/// hand.
class _SlowPollApi extends FakeWhenIsBinsApi {
  _SlowPollApi({
    this.expectedWaitSeconds,
    this.progressMessage,
    this.queueAhead,
  });

  final int? expectedWaitSeconds;
  final String? progressMessage;
  final int? queueAhead;
  final _wait = Completer<LookupWait>();

  @override
  Future<Lookup> createLookup(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async {
    createLookupCalls++;
    lookupBodies.add(body);
    return Lookup(
      id: 'lookup-1',
      status: 'queued',
      expectedWaitSeconds: expectedWaitSeconds,
      queueAhead: queueAhead,
      progress: progressMessage == null
          ? null
          : LookupProgress(stage: 'council', message: progressMessage),
    );
  }

  @override
  Future<LookupWait> waitForLookup(String lookupId, {String? after}) {
    return _wait.future;
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
    String? notes,
    String? calendarUrl,
  }) {
    return Schedule(
      propertyId: 'p:4c5ee6c2f2c7c959',
      addressMatch: 'exact',
      provisional: provisional,
      dateConfidence: dateConfidence,
      dateCompleteness: dateCompleteness,
      notes: notes,
      calendarUrl: calendarUrl,
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

  group('the loading state', () {
    /// Opens the schedule screen while [lookup] is still in flight.
    Future<void> openWhileLoading(
      WidgetTester tester,
      SettingsProvider settings,
      LookupProvider lookup,
    ) async {
      await tester.pumpWidget(buildHostedSchedule(settings, lookup));
      await tester.tap(find.text('Open your bin days'));
      // Not pumpAndSettle: the spinner never stops, so the route transition is
      // pumped by hand.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('says how long this council usually takes', (tester) async {
      final settings = await makeSettings();
      final api = _SlowPollApi(
        expectedWaitSeconds: 60,
        progressMessage: 'Asking your council for your dates',
        queueAhead: 3,
      );
      final lookup = LookupProvider(api: api);
      unawaited(lookup.submitLookup(postcode: 'CB4 2HX', address: const {}));

      await openWhileLoading(tester, settings, lookup);

      expect(find.textContaining('Finding your bin days'), findsOneWidget);
      expect(find.text('Usually about a minute for this council'),
          findsOneWidget);
      expect(find.text('Asking your council for your dates'), findsOneWidget);
      expect(find.text('there are 3 other lookups ahead'), findsOneWidget);
    });

    testWidgets('says the wait in seconds when it is not a whole minute',
        (tester) async {
      final settings = await makeSettings();
      final api = _SlowPollApi(expectedWaitSeconds: 45);
      final lookup = LookupProvider(api: api);
      unawaited(lookup.submitLookup(postcode: 'CB4 2HX', address: const {}));

      await openWhileLoading(tester, settings, lookup);

      expect(find.text('Usually about 45 seconds for this council'),
          findsOneWidget);
    });

    testWidgets('falls back to the council the address lookup named',
        (tester) async {
      final settings = await makeSettings();
      final api = _SlowPollApi()
        ..addressLookup = const AddressLookup(
          postcode: 'CB4 2HX',
          requiredInput: 'none',
          council: Council(
            id: 'E07000008',
            name: 'Cambridge City Council',
            expectedWaitSeconds: 30,
          ),
        );
      final lookup = LookupProvider(api: api);
      await lookup.lookupPostcode('CB4 2HX');
      unawaited(lookup.submitLookup(postcode: 'CB4 2HX', address: const {}));

      await openWhileLoading(tester, settings, lookup);

      expect(find.text('Usually about 30 seconds for this council'),
          findsOneWidget);
    });

    testWidgets('says nothing it cannot back up', (tester) async {
      final settings = await makeSettings();
      final api = _SlowPollApi();
      final lookup = LookupProvider(api: api);
      unawaited(lookup.submitLookup(postcode: 'CB4 2HX', address: const {}));

      await openWhileLoading(tester, settings, lookup);

      expect(find.textContaining('Usually about'), findsNothing);
      expect(find.textContaining('other lookups ahead'), findsNothing);
    });
  });

  group('councilWaitCopy', () {
    test('a whole minute reads as a minute', () {
      expect(
        councilWaitCopy(60),
        'Usually about a minute for this council',
      );
    });

    test('anything else is the seconds it is', () {
      expect(
        councilWaitCopy(45),
        'Usually about 45 seconds for this council',
      );
      expect(
        councilWaitCopy(120),
        'Usually about 120 seconds for this council',
      );
    });

    test('says nothing when there is no honest figure', () {
      expect(councilWaitCopy(null), isNull);
      expect(councilWaitCopy(0), isNull);
      expect(councilWaitCopy(-5), isNull);
    });
  });

  group('cleanScheduleNotes', () {
    test('drops a bracketed source annotation', () {
      expect(
        cleanScheduleNotes(
          'Parsed from the South Kesteven self-service form (renderform '
          't=213), which lists collections week-by-week.',
        ),
        'Parsed from the South Kesteven self-service form, which lists '
        'collections week-by-week.',
      );
    });

    test('drops every bracketed token, collapsing the gap', () {
      expect(
        cleanScheduleNotes(
          'Communal bins (see website) (shared) are collected together.',
        ),
        'Communal bins are collected together.',
      );
    });

    test('leaves a note without brackets alone', () {
      expect(
        cleanScheduleNotes('Bank holidays shift collections by a day.'),
        'Bank holidays shift collections by a day.',
      );
    });

    test('returns null when there is nothing left to say', () {
      expect(cleanScheduleNotes(null), isNull);
      expect(cleanScheduleNotes('(renderform t=213)'), isNull);
      expect(cleanScheduleNotes('   '), isNull);
    });
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

  testWidgets('a rate-limited lookup shows the friendly message, not the API '
      'detail', (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup =
          AddressLookup(postcode: 'CB4 2HX', requiredInput: 'none');
    final lookup = LookupProvider(api: api);
    await lookup.lookupPostcode('CB4 2HX');
    api.error = ApiException(
      statusCode: 429,
      problem: 'rate_limited',
      detail: 'Anonymous allowance exhausted (10 lookups a minute).',
    );
    await lookup.submitLookup(postcode: 'CB4 2HX', address: const {});

    await tester.pumpWidget(buildHostedSchedule(settings, lookup));
    await openSchedule(tester);

    expect(find.text('We could not load your bin days.'), findsOneWidget);
    expect(
      find.text('Lots of people are checking bin days right now. '
          'Try again in a minute.'),
      findsOneWidget,
    );
    expect(find.textContaining('Anonymous allowance'), findsNothing);
  });

  testWidgets('shows the council caveats as a muted line', (tester) async {
    final settings = await makeSettings();
    const notes = 'Assisted collections move back a day after a bank holiday.';
    final note = find.text(notes);

    await tester.pumpWidget(
      buildScheduleApp(settings, schedule(notes: notes), theme: AppTheme.light),
    );

    expect(note, findsOneWidget);
    expect(textColour(tester, note), AppColors.muted,
        reason: 'a caveat is secondary to the dates it qualifies');
    // The caveat sits with the address it applies to, above the next date.
    expect(
      tester.getTopLeft(note).dy,
      lessThan(tester.getTopLeft(find.text('Put out: Black bin')).dy),
    );
  });

  testWidgets('shows no caveat line when the council published none',
      (tester) async {
    final settings = await makeSettings();

    await tester.pumpWidget(buildScheduleApp(settings, schedule()));

    expect(find.text(''), findsNothing,
        reason: 'an empty caveat must not leave a blank line');
  });

  testWidgets('hides the API source annotation from the notes',
      (tester) async {
    final settings = await makeSettings();
    const notes =
        'Parsed from the South Kesteven self-service form (renderform t=213), '
        'which lists collections week-by-week.';

    await tester.pumpWidget(
      buildScheduleApp(settings, schedule(notes: notes), theme: AppTheme.light),
    );

    expect(find.textContaining('renderform'), findsNothing);
    expect(
      find.text(
        'Parsed from the South Kesteven self-service form, which lists '
        'collections week-by-week.',
      ),
      findsOneWidget,
    );
  });

  group('add to calendar', () {
    const calendarUrl = 'https://whenisbins.com/100023336956.ics';

    late List<String> launched;
    late List<String> clipboard;

    setUp(() {
      launched = [];
      clipboard = [];
    });

    /// Runs [body] with the platform the widgets see pinned to [platform].
    ///
    /// The override is cleared inside the test body: the framework checks its
    /// debug variables at the end of the body, BEFORE addTearDown runs, so a
    /// deferred reset fails every test that used it.
    Future<void> onPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    /// Captures what the app hands to the OS launcher. In a test the platform
    /// implementation is the method-channel one, so this is the URL the device
    /// would actually open.
    void mockLaunch(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch') {
            launched.add(call.arguments['url'] as String);
          }
          return true;
        },
      );
    }

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
    }

    Future<void> tapCalendarAction(WidgetTester tester, Finder action) async {
      await tester.ensureVisible(action);
      await tester.pump();
      await tester.tap(action);
      await tester.pump();
    }

    testWidgets('on iOS it opens the calendar subscribe sheet', (tester) async {
      mockLaunch(tester);
      final settings = await makeSettings();

      await onPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(
          buildScheduleApp(settings, schedule(calendarUrl: calendarUrl)),
        );
        await tapCalendarAction(tester, find.text('Open calendar feed'));

        expect(launched, ['webcal://whenisbins.com/100023336956.ics'],
            reason: 'webcal is what makes iOS offer to subscribe');
      });
    });

    testWidgets('on Android it offers the link to copy instead',
        (tester) async {
      mockClipboard(tester);
      final settings = await makeSettings();

      await onPlatform(TargetPlatform.android, () async {
        await tester.pumpWidget(
          buildScheduleApp(settings, schedule(calendarUrl: calendarUrl)),
        );

        final action = find.text('Copy calendar link');
        expect(action, findsOneWidget);
        expect(find.text('Paste it into your calendar app.'), findsOneWidget);
        expect(find.text('Open calendar feed'), findsNothing,
            reason: 'Android has no handler for a webcal or .ics URL');

        await tapCalendarAction(tester, action);

        expect(clipboard, [calendarUrl]);
      });
    });
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

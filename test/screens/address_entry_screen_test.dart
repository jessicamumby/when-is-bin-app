import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/address_entry_screen.dart';

import '../fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A collection three days out, so the schedule always has an upcoming date.
  final nextCollection = DateTime.now().add(const Duration(days: 3));
  final nextCollectionIso = DateFormat('yyyy-MM-dd').format(nextCollection);

  Schedule schedule() {
    return Schedule(
      propertyId: 'p:4c5ee6c2f2c7c959',
      addressMatch: 'exact',
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

  Future<SettingsProvider> makeSettings() async {
    SharedPreferences.setMockInitialValues({});
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  AddressLookup lookupNeeding(
    String requiredInput, {
    String postcode = 'EH14 7AL',
    InputOptions? inputOptions,
  }) {
    return AddressLookup(
      postcode: postcode,
      requiredInput: requiredInput,
      council: const Council(id: 'S12000036', name: 'City of Edinburgh Council'),
      inputOptions: inputOptions,
    );
  }

  Widget buildScreen(
    LookupProvider lookup,
    SettingsProvider settings,
    AddressLookup addressLookup,
  ) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: MaterialApp(
        home: AddressEntryScreen(addressLookup: addressLookup),
      ),
    );
  }

  /// Taps the submit button, scrolling it into view first: a long form (the
  /// weekday picker especially) pushes it below the 600px test viewport, where
  /// a bare tap misses silently.
  Future<void> submitForm(WidgetTester tester, {bool settle = true}) async {
    final button = find.text('Find my bin day');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('a property journey sends the first line of the address',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('property')),
    );

    expect(find.text('First line of your address'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '15 Example Court');
    await submitForm(tester);

    expect(api.lastLookupBody, {
      'postcode': 'EH14 7AL',
      'property': '15 Example Court',
    });
    // The address and its schedule are kept, and the bin days are on screen.
    expect(settings.savedPropertyId, 'p:4c5ee6c2f2c7c959');
    expect(settings.savedPostcode, 'EH14 7AL');
    expect(settings.savedAddress, '15 Example Court, EH14 7AL');
    expect(settings.hasSavedSchedule, isTrue);
    expect(find.text('Put out: Black bin'), findsOneWidget);
  });

  testWidgets('a blank property is refused before anything is sent',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi();
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('property')),
    );
    await submitForm(tester, settle: false);

    expect(find.text('Enter the first line of your address.'), findsOneWidget);
    expect(api.createLookupCalls, 0);
    expect(settings.savedAddress, isNull);
  });

  testWidgets('a street journey offers the council\u2019s roads to pick from',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding(
      'street',
      inputOptions: const InputOptions(
        field: 'street',
        needsMoreQuery: false,
        notListedValue: '__not_listed__',
        options: [
          InputOption(
            value: 'A70--Glenbrook Rd To B7031',
            label: 'A70--Glenbrook Rd To B7031',
          ),
          InputOption(value: 'B7031--Currie', label: 'B7031--Currie'),
        ],
      ),
    );

    await tester.pumpWidget(buildScreen(lookup, settings, addressLookup));

    expect(find.text('A70--Glenbrook Rd To B7031'), findsOneWidget);
    expect(find.text('B7031--Currie'), findsOneWidget);

    await tester.tap(find.text('B7031--Currie'));
    await tester.pump();
    await submitForm(tester);

    expect(api.lastLookupBody, {
      'postcode': 'EH14 7AL',
      'street': 'B7031--Currie',
    });
  });

  testWidgets('"none of these" falls back to typing, and never sends the '
      'not-listed value', (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding(
      'street',
      inputOptions: const InputOptions(
        field: 'street',
        needsMoreQuery: false,
        notListedValue: '__not_listed__',
        options: [
          InputOption(
            value: 'A70--Glenbrook Rd To B7031',
            label: 'A70--Glenbrook Rd To B7031',
          ),
        ],
      ),
    );

    await tester.pumpWidget(buildScreen(lookup, settings, addressLookup));

    await tester.tap(find.text('None of these'));
    await tester.pump();

    expect(find.text('A70--Glenbrook Rd To B7031'), findsNothing);
    expect(find.text('Street'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'My Own Road');
    await submitForm(tester);

    expect(api.lastLookupBody?['street'], 'My Own Road');
    expect(api.lastLookupBody?['street'], isNot('__not_listed__'));
  });

  testWidgets('choosing "none of these" with nothing typed is refused',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi();
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding(
      'street',
      inputOptions: const InputOptions(
        field: 'street',
        needsMoreQuery: false,
        notListedValue: '__not_listed__',
        options: [
          InputOption(value: 'A70--Glenbrook', label: 'A70--Glenbrook'),
        ],
      ),
    );

    await tester.pumpWidget(buildScreen(lookup, settings, addressLookup));

    await tester.tap(find.text('None of these'));
    await tester.pump();
    await submitForm(tester, settle: false);

    expect(api.createLookupCalls, 0,
        reason: 'the not-listed sentinel must never be submitted');
    expect(find.text('Enter or pick your street.'), findsOneWidget);
  });

  testWidgets('a short-list council lets the user search for their road',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookupResponses = [
        lookupNeeding(
          'street',
          inputOptions: const InputOptions(
            field: 'street',
            needsMoreQuery: true,
            notListedValue: '__not_listed__',
          ),
        ),
        lookupNeeding(
          'street',
          inputOptions: const InputOptions(
            field: 'street',
            needsMoreQuery: true,
            notListedValue: '__not_listed__',
            options: [
              InputOption(
                value: 'A70--Glenbrook Rd To B7031',
                label: 'A70--Glenbrook Rd To B7031',
              ),
            ],
          ),
        ),
      ];
    final lookup = LookupProvider(api: api);
    await lookup.lookupPostcode('EH14 7AL');

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookup.addressLookup!),
    );

    expect(find.text('A70--Glenbrook Rd To B7031'), findsNothing);
    expect(find.text('Search for your street or area'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A70');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(api.lastAddressQuery, 'A70');
    expect(find.text('A70--Glenbrook Rd To B7031'), findsOneWidget);
  });

  testWidgets('a road-and-locality journey asks for both', (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('road_and_locality')),
    );

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'Example Road');
    await tester.enterText(find.byType(TextField).at(1), 'Cambridge');
    await submitForm(tester);

    expect(api.lastLookupBody, {
      'postcode': 'EH14 7AL',
      'street': 'Example Road',
      'locality': 'Cambridge',
    });
  });

  testWidgets('a settlement journey picks from the council\u2019s own list',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding(
      'settlement_or_road',
      inputOptions: const InputOptions(
        field: 'locality',
        needsMoreQuery: false,
        notListedValue: '__not_listed__',
        options: [
          InputOption(value: 'Currie', label: 'Currie'),
          InputOption(value: 'Balerno', label: 'Balerno'),
        ],
      ),
    );

    await tester.pumpWidget(buildScreen(lookup, settings, addressLookup));

    // The picker sits in the Area slot: the API named `locality` as its field.
    expect(find.text('Balerno'), findsOneWidget);
    await tester.tap(find.text('Balerno'));
    await tester.pump();
    await submitForm(tester);

    expect(api.lastLookupBody, {'postcode': 'EH14 7AL', 'locality': 'Balerno'});
    expect(settings.savedAddress, 'Balerno, EH14 7AL');
  });

  testWidgets('a weekday journey offers Monday to Sunday', (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('normal_weekday')),
    );

    for (final day in const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ]) {
      expect(find.text(day), findsOneWidget);
    }

    await tester.tap(find.text('Monday'));
    await tester.pump();
    await submitForm(tester);

    expect(api.lastLookupBody, {
      'postcode': 'EH14 7AL',
      'normal_weekday': 'Monday',
    });
  });

  testWidgets('a weekday journey is refused without a day', (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi();
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('normal_weekday')),
    );
    await submitForm(tester, settle: false);

    expect(find.text('Choose the day your bins are usually collected.'),
        findsOneWidget);
    expect(api.createLookupCalls, 0);
  });

  testWidgets('a property-type journey offers the four types the API accepts',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(
        lookup,
        settings,
        lookupNeeding('property_type', postcode: 'CB4 2HX'),
      ),
    );

    expect(find.text('A private flat with no bin store'), findsOneWidget);
    expect(find.text('A private block with a bin store'), findsOneWidget);
    expect(find.text('A housing estate'), findsOneWidget);
    expect(find.text('Bags collected from the street'), findsOneWidget);

    await tester.tap(find.text('A housing estate'));
    await tester.pump();
    await submitForm(tester);

    expect(api.lastLookupBody, {
      'postcode': 'CB4 2HX',
      'property_type': 'housing_estate',
    });
  });

  testWidgets('a postcode-only journey submits the postcode alone',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done', result: schedule())];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('none')),
    );

    expect(find.byType(TextField), findsNothing);
    await submitForm(tester);

    expect(api.lastLookupBody, {'postcode': 'EH14 7AL'});
    expect(find.text('Put out: Black bin'), findsOneWidget);
  });

  testWidgets('a failed lookup keeps the user on the form and saves nothing',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [
        Lookup(
          id: 'lookup-1',
          status: 'failed',
          detail: "The council's system doesn't list that road.",
        ),
      ];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('property')),
    );
    await tester.enterText(find.byType(TextField), '1 Nowhere Road');
    await submitForm(tester);

    expect(find.text("The council's system doesn't list that road."),
        findsOneWidget);
    expect(settings.savedAddress, isNull);
    expect(settings.hasSavedSchedule, isFalse);
    expect(find.text('Find my bin day'), findsOneWidget,
        reason: 'the form is still there to correct');
    expect(find.text('Try another postcode'), findsOneWidget);
  });

  testWidgets('a failed lookup offers a way back to the postcode screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [
        Lookup(id: 'lookup-1', status: 'failed', detail: 'No address matched.'),
      ];
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding('property');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => lookup),
          ChangeNotifierProvider(create: (_) => settings),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddressEntryScreen(addressLookup: addressLookup),
                    ),
                  ),
                  child: const Text('postcode screen'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('postcode screen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1 Nowhere Road');
    await submitForm(tester);

    final startOver = find.text('Try another postcode');
    await tester.ensureVisible(startOver);
    await tester.pump();
    await tester.tap(startOver);
    await tester.pumpAndSettle();

    expect(find.text('postcode screen'), findsOneWidget);
  });

  testWidgets('a slow lookup still saves the partial result and its address',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
      ..waitResponses = [
        Lookup(id: 'lookup-1', status: 'partial', result: schedule()),
      ];
    // A clock that jumps forward by whatever the provider waits for, so the
    // two-minute budget is spent without the test waiting two minutes.
    var clock = DateTime(2026, 9, 23, 12);
    final lookup = LookupProvider(
      api: api,
      now: () => clock,
      delay: (duration) async => clock = clock.add(duration),
    );

    await tester.pumpWidget(
      buildScreen(lookup, settings, lookupNeeding('property')),
    );
    await tester.enterText(find.byType(TextField), '15 Example Court');
    await submitForm(tester);

    expect(lookup.pendingLookupId, 'lookup-1');
    expect(settings.hasSavedSchedule, isTrue);
    expect(find.text('Put out: Black bin'), findsOneWidget);
  });

  testWidgets('the screen watches the provider for a narrowed option list',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi();
    final lookup = LookupProvider(api: api);
    final addressLookup = lookupNeeding(
      'street',
      inputOptions: const InputOptions(
        field: 'street',
        needsMoreQuery: true,
        notListedValue: '__not_listed__',
      ),
    );

    await tester.pumpWidget(buildScreen(lookup, settings, addressLookup));

    // The form is built from the lookup it was handed...
    expect(find.text('City of Edinburgh Council \u2022 EH14 7AL'), findsOneWidget);

    // ...and a provider that resolves a different journey rebuilds it.
    api.addressLookupResponses = [
      lookupNeeding(
        'property_type',
        postcode: 'CB4 2HX',
        inputOptions: null,
      ),
    ];
    await lookup.lookupPostcode('CB4 2HX');
    await tester.pumpAndSettle();

    expect(find.text('A housing estate'), findsOneWidget);
    expect(find.text('Search for your street or area'), findsNothing);
  });
}

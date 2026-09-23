import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';

import '../fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A collection three days out, so the persisted schedule always has an
  /// upcoming date no matter when the suite runs.
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

  Future<SettingsProvider> makeSettings({
    String? address,
    String? postcode,
    String? propertyId,
    String? schedule,
  }) async {
    SharedPreferences.setMockInitialValues({
      'saved_address': ?address,
      'saved_postcode': ?postcode,
      'saved_property_id': ?propertyId,
      'saved_schedule': ?schedule,
    });
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  Widget buildApp(SettingsProvider settings, LookupProvider lookup) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('shows the postcode entry form', (tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(
      buildApp(settings, LookupProvider(api: FakeWhenIsBinsApi())),
    );

    expect(find.text('Find your bin day'), findsOneWidget);
    expect(find.text('Postcode'), findsOneWidget);
    expect(find.text('Find my bin day'), findsOneWidget);
  });

  testWidgets('shows a validation error for an empty postcode',
      (tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(
      buildApp(settings, LookupProvider(api: FakeWhenIsBinsApi())),
    );

    await tester.tap(find.text('Find my bin day'));
    await tester.pump();

    expect(find.text('Enter a postcode.'), findsOneWidget);
  });

  testWidgets('shows the saved-address shortcut when one is saved',
      (tester) async {
    final settings = await makeSettings(
      address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      postcode: 'CB4 2HX',
      propertyId: 'p:4c5ee6c2f2c7c959',
    );
    await tester.pumpWidget(
      buildApp(settings, LookupProvider(api: FakeWhenIsBinsApi())),
    );

    expect(find.text('Your saved address'), findsOneWidget);
    expect(find.text('View your bin days'), findsOneWidget);
  });

  testWidgets('the settings gear opens the settings screen', (tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(
      buildApp(settings, LookupProvider(api: FakeWhenIsBinsApi())),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Reminder time'), findsOneWidget);
    expect(find.text('Find your bin day'), findsNothing);
  });

  testWidgets('hydrates the saved schedule on a cold start', (tester) async {
    final settings = await makeSettings(
      address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      postcode: 'CB4 2HX',
      propertyId: 'p:4c5ee6c2f2c7c959',
      schedule: savedScheduleJson(),
    );
    final lookup = LookupProvider(api: FakeWhenIsBinsApi());

    await tester.pumpWidget(buildApp(settings, lookup));
    await tester.pump();

    expect(lookup.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
    expect(lookup.schedule?.collections.single.name, 'Black bin');
  });

  testWidgets('View your bin days shows the saved schedule, not the empty state',
      (tester) async {
    final settings = await makeSettings(
      address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      postcode: 'CB4 2HX',
      propertyId: 'p:4c5ee6c2f2c7c959',
      schedule: savedScheduleJson(),
    );
    await tester.pumpWidget(
      buildApp(settings, LookupProvider(api: FakeWhenIsBinsApi())),
    );

    await tester.tap(find.text('View your bin days'));
    await tester.pumpAndSettle();

    expect(find.text('No schedule yet. Search for your postcode first.'),
        findsNothing);
    expect(find.text(nextCollectionLabel), findsOneWidget);
    expect(find.text('Put out: Black bin'), findsOneWidget);
    expect(find.text('15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX'), findsOneWidget);
  });

  Future<void> submitPostcode(WidgetTester tester, String postcode) async {
    await tester.enterText(find.byType(TextField), postcode);
    await tester.tap(find.text('Find my bin day'));
    await tester.pumpAndSettle();
  }

  testWidgets('a council with a candidate list opens the address picker',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup = AddressLookup(
        postcode: 'CB4 2HX',
        requiredInput: 'property_id',
        council: const Council(id: 'E07000008', name: 'Cambridge City Council'),
        candidates: const [
          AddressCandidate(
            id: 'p:4c5ee6c2f2c7c959',
            label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
          ),
        ],
      );

    await tester.pumpWidget(buildApp(settings, LookupProvider(api: api)));
    await submitPostcode(tester, 'CB4 2HX');

    expect(find.text('15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX'), findsOneWidget);
  });

  testWidgets('a council that needs more than a postcode opens the address form',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup = AddressLookup(
        postcode: 'EH14 7AL',
        requiredInput: 'street',
        council: const Council(id: 'S12000036', name: 'City of Edinburgh Council'),
        inputOptions: const InputOptions(
          field: 'street',
          needsMoreQuery: false,
          notListedValue: '__not_listed__',
          options: [
            InputOption(value: 'A70--Glenbrook', label: 'A70--Glenbrook'),
          ],
        ),
      );

    await tester.pumpWidget(buildApp(settings, LookupProvider(api: api)));
    await submitPostcode(tester, 'EH14 7AL');

    expect(find.text('A few more details'), findsOneWidget);
    expect(find.text('A70--Glenbrook'), findsOneWidget);
    expect(
      find.text('This council needs more information. Please try again later.'),
      findsNothing,
    );
  });

  testWidgets('a postcode-only council goes straight to the form that submits it',
      (tester) async {
    final settings = await makeSettings();
    final api = FakeWhenIsBinsApi()
      ..addressLookup = AddressLookup(
        postcode: 'CB4 2HX',
        requiredInput: 'none',
        council: const Council(id: 'E07000008', name: 'Cambridge City Council'),
      );

    await tester.pumpWidget(buildApp(settings, LookupProvider(api: api)));
    await submitPostcode(tester, 'CB4 2HX');

    expect(find.text('A few more details'), findsOneWidget);
    expect(find.text('Find my bin day'), findsOneWidget);
    expect(
      find.text('This council needs more information. Please try again later.'),
      findsNothing,
    );
  });
}

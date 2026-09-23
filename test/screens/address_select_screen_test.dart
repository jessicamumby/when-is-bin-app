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
import 'package:when_is_bin_app/screens/address_select_screen.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';

import '../fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const candidate = AddressCandidate(
    id: 'p:4c5ee6c2f2c7c959',
    label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
  );

  final addressLookup = AddressLookup(
    postcode: 'CB4 2HX',
    requiredInput: 'property_id',
    council: const Council(id: 'E07000008', name: 'Cambridge City Council'),
    candidates: const [candidate],
  );

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

  Widget buildApp(
    LookupProvider lookup,
    SettingsProvider settings, {
    ThemeData? theme,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: MaterialApp(
        theme: theme,
        home: AddressSelectScreen(addressLookup: addressLookup),
      ),
    );
  }

  Color? textColour(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style?.color;

  testWidgets('renders its own tokens for the active brightness',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      buildApp(
        LookupProvider(api: FakeWhenIsBinsApi()),
        SettingsProvider(await SharedPreferences.getInstance()),
        theme: AppTheme.dark,
      ),
    );

    expect(
      textColour(tester, find.text('Cambridge City Council \u2022 CB4 2HX')),
      AppColors.mutedDark,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color,
      AppColors.tealDark,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.chevron_right)).color,
      AppColors.mutedDark,
    );
  });

  testWidgets('keeps its light tokens in light mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      buildApp(
        LookupProvider(api: FakeWhenIsBinsApi()),
        SettingsProvider(await SharedPreferences.getInstance()),
        theme: AppTheme.light,
      ),
    );

    expect(
      textColour(tester, find.text('Cambridge City Council \u2022 CB4 2HX')),
      AppColors.muted,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color,
      AppColors.teal,
    );
  });

  Widget buildHome(LookupProvider lookup, SettingsProvider settings) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => lookup),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('picking an address saves it along with the schedule',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsProvider(prefs);
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [
        Lookup(id: 'lookup-1', status: 'done', result: schedule()),
      ];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(buildApp(lookup, settings));
    await tester.tap(find.text(candidate.label));
    await tester.pumpAndSettle();

    expect(settings.savedAddress, candidate.label);
    expect(settings.savedPostcode, 'CB4 2HX');
    expect(settings.savedPropertyId, 'p:4c5ee6c2f2c7c959');
    expect(settings.hasSavedSchedule, isTrue);
    expect(settings.savedCollections.single.name, 'Black bin');

    // The schedule survives a cold start.
    final reloaded = SettingsProvider(prefs);
    expect(reloaded.hasSavedSchedule, isTrue);
    expect(reloaded.savedSchedule?.propertyId, 'p:4c5ee6c2f2c7c959');
    expect(reloaded.savedSchedule?.collections.single.name, 'Black bin');

    expect(find.text('No schedule yet. Search for your postcode first.'),
        findsNothing);
  });

  testWidgets('a picked address shows real bin days after a relaunch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Session 1: the user picks their address.
    await tester.pumpWidget(
      buildApp(
        LookupProvider(
          api: FakeWhenIsBinsApi()
            ..lookupResponses = [
              Lookup(id: 'lookup-1', status: 'done', result: schedule()),
            ],
        ),
        SettingsProvider(prefs),
      ),
    );
    await tester.tap(find.text(candidate.label));
    await tester.pumpAndSettle();

    // Session 2: a cold start. Pump an empty tree first so the old routes are
    // disposed — a bare pumpWidget would reuse the existing Navigator.
    await tester.pumpWidget(const SizedBox.shrink());
    final lookup = LookupProvider(api: FakeWhenIsBinsApi());
    await tester.pumpWidget(buildHome(lookup, SettingsProvider(prefs)));
    await tester.pump();

    expect(find.text('Your saved address'), findsOneWidget);
    await tester.tap(find.text('View your bin days'));
    await tester.pumpAndSettle();

    expect(find.text('No schedule yet. Search for your postcode first.'),
        findsNothing);
    expect(find.text('Put out: Black bin'), findsOneWidget);
  });

  testWidgets('does not save an address when the lookup fails', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    final api = FakeWhenIsBinsApi()
      ..lookupResponses = [
        Lookup(
          id: 'lookup-1',
          status: 'failed',
          detail: "The council's system doesn't list that exact address.",
        ),
      ];
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(buildApp(lookup, settings));
    await tester.tap(find.text(candidate.label));
    await tester.pumpAndSettle();

    expect(settings.savedAddress, isNull);
    expect(settings.hasSavedSchedule, isFalse);
    expect(
      find.text("The council's system doesn't list that exact address."),
      findsOneWidget,
    );
  });
}

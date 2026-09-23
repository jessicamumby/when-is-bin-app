import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';

import '../fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsProvider> makeSettings({
    String? address,
    String? postcode,
    String? propertyId,
  }) async {
    SharedPreferences.setMockInitialValues({
      'saved_address': ?address,
      'saved_postcode': ?postcode,
      'saved_property_id': ?propertyId,
    });
    return SettingsProvider(await SharedPreferences.getInstance());
  }

  Widget buildApp(SettingsProvider settings) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => LookupProvider(api: FakeWhenIsBinsApi()),
        ),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('shows the postcode entry form', (tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(buildApp(settings));

    expect(find.text('Find your bin day'), findsOneWidget);
    expect(find.text('Postcode'), findsOneWidget);
    expect(find.text('Find my bin day'), findsOneWidget);
  });

  testWidgets('shows a validation error for an empty postcode',
      (tester) async {
    final settings = await makeSettings();
    await tester.pumpWidget(buildApp(settings));

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
    await tester.pumpWidget(buildApp(settings));

    expect(find.text('Your saved address'), findsOneWidget);
    expect(find.text('View your bin days'), findsOneWidget);
  });
}

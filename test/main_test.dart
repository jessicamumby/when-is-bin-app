import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/main.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';

import 'fakes/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app() async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LookupProvider(api: FakeWhenIsBinsApi())),
        ChangeNotifierProvider(create: (_) => settings),
      ],
      child: const WhenIsBinApp(),
    );
  }

  ThemeData themeOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HomeScreen)));

  testWidgets('follows the system into dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(await app());
    await tester.pump();

    expect(themeOf(tester).brightness, Brightness.dark);
    expect(
      themeOf(tester).scaffoldBackgroundColor,
      AppColors.canvasDark,
    );
  });

  testWidgets('follows the system back into light mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(await app());
    await tester.pump();

    expect(themeOf(tester).brightness, Brightness.light);
    expect(themeOf(tester).scaffoldBackgroundColor, AppColors.paper);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/about_screen.dart';
import 'package:when_is_bin_app/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app(ThemeData theme) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    return ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(theme: theme, home: const SettingsScreen()),
    );
  }

  Color? textColour(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style?.color;

  const secondary = 'When should we remind you to put the bins out?';

  testWidgets('renders its secondary text with the dark token',
      (tester) async {
    await tester.pumpWidget(await app(AppTheme.dark));

    expect(textColour(tester, find.text(secondary)), AppColors.mutedDark);
    expect(
      textColour(tester, find.text('No address saved.')),
      AppColors.mutedDark,
    );
  });

  testWidgets('renders its secondary text with the light token',
      (tester) async {
    await tester.pumpWidget(await app(AppTheme.light));

    expect(textColour(tester, find.text(secondary)), AppColors.muted);
    expect(textColour(tester, find.text('No address saved.')), AppColors.muted);
  });

  testWidgets('offers About and opens it', (tester) async {
    await tester.pumpWidget(await app(AppTheme.light));

    expect(find.text('About'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/build_info.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/about_screen.dart';
import 'package:when_is_bin_app/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app(ThemeData theme, {Map<String, Object>? prefs}) async {
    SharedPreferences.setMockInitialValues(prefs ?? {});
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

  testWidgets('names the build it is running at the foot of the screen',
      (tester) async {
    await tester.pumpWidget(await app(AppTheme.light));

    // 'Build dev' under a plain `flutter test`; the real short SHA when the
    // build passes --dart-define=GIT_SHA.
    final stamp = find.text('Build $kGitSha');
    await tester.scrollUntilVisible(stamp, 100);
    expect(stamp, findsOneWidget);
    expect(textColour(tester, stamp), AppColors.muted);
  });

  group('when the dates were last checked', () {
    const saved = <String, Object>{
      'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
      'saved_postcode': 'CB4 2HX',
      'saved_property_id': 'p:4c5ee6c2f2c7c959',
    };

    testWidgets('names the day and time of the last check', (tester) async {
      // Stored in UTC, shown in the phone's own time.
      final checkedAt = DateTime(2026, 10, 5, 14, 2);
      await tester.pumpWidget(
        await app(
          AppTheme.light,
          prefs: {
            ...saved,
            'schedule_checked_at': checkedAt.toUtc().toIso8601String(),
          },
        ),
      );

      final line = find.text('Dates last checked: Monday 5 October, 14:02');
      expect(line, findsOneWidget);
      expect(textColour(tester, line), AppColors.muted);
    });

    testWidgets('says nothing before the first check', (tester) async {
      await tester.pumpWidget(await app(AppTheme.light, prefs: saved));

      expect(find.textContaining('Dates last checked'), findsNothing);
    });

    testWidgets('says nothing once the address is removed', (tester) async {
      await tester.pumpWidget(
        await app(
          AppTheme.light,
          prefs: {
            'schedule_checked_at': DateTime(2026, 10, 5, 14, 2)
                .toUtc()
                .toIso8601String(),
          },
        ),
      );

      expect(find.textContaining('Dates last checked'), findsNothing);
    });
  });
}

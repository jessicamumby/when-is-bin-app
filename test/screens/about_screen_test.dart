import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/screens/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sourcesUrl = 'https://whenisbins.com/sources';
  const privacyUrl = 'https://whenisbins.com/privacy';
  const agentsUrl =
      'https://loosemore.com/2026/02/25/ai-agents-will-join-up-government-before-government-does/';

  /// Builds the screen with a link opener that records instead of launching, so
  /// the test asserts which URL a tap would open without a real browser.
  Future<List<Uri>> pumpAbout(WidgetTester tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        // Mirrors main.dart: the app is light-only, so a dark-mode device must
        // not repaint this screen.
        themeMode: ThemeMode.light,
        home: AboutScreen(
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    return opened;
  }

  group('AboutScreen', () {
    testWidgets('says what the app does', (tester) async {
      await pumpAbout(tester);

      expect(find.text('About'), findsOneWidget);
      expect(
        find.textContaining('When Is Bins tells you when to put your bins out'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Add the dates to your calendar or get an email reminder',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('All of it built by LLMs'), findsOneWidget);
    });

    testWidgets('names the operator and the limits of the service',
        (tester) async {
      await pumpAbout(tester);

      expect(
        find.textContaining(
          'a free, independent demonstrator operated and funded by Public '
          'Digital Limited',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Coverage and the dates available vary'),
        findsOneWidget,
      );
      expect(find.textContaining('hello@whenisbins.com'), findsOneWidget);
      expect(
        find.textContaining('Your council handles missed collections'),
        findsOneWidget,
      );
    });

    testWidgets('closes on the point of the demonstrator', (tester) async {
      await pumpAbout(tester);

      expect(
        find.textContaining(
          "But a UK-wide bin day website isn\u2019t the point",
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('what\u2019s coming is'),
        findsOneWidget,
      );
    });

    testWidgets('opens Sources, Privacy and the AI agents piece',
        (tester) async {
      final opened = await pumpAbout(tester);

      await tester.tap(find.text('Sources'));
      await tester.pump();
      expect(opened, [Uri.parse(sourcesUrl)]);

      await tester.tap(find.text('Privacy'));
      await tester.pump();
      expect(opened, [Uri.parse(sourcesUrl), Uri.parse(privacyUrl)]);

      await tester.tap(find.text('AI agents'));
      await tester.pump();
      expect(opened, [
        Uri.parse(sourcesUrl),
        Uri.parse(privacyUrl),
        Uri.parse(agentsUrl),
      ]);
    });

    testWidgets('renders in the light design system on any device theme',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pumpAbout(tester);

      final theme = Theme.of(tester.element(find.byType(AboutScreen)));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColors.paper);
    });
  });
}
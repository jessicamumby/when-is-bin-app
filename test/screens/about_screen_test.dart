import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

    testWidgets('announces the inline links as buttons, and only the links',
        (tester) async {
      // A GestureDetector around a Text is invisible to assistive tech: no
      // button role, nothing to tap by voice. These three links are the only
      // way out of the app from this screen.
      final handle = tester.ensureSemantics();

      await pumpAbout(tester);

      // This Flutter has no SemanticsTester/includesNodeWith any more, so walk
      // the tree the way a screen reader would.
      final buttonLabels = <String>{};
      void walk(SemanticsNode node) {
        final data = node.getSemanticsData();
        if (data.flagsCollection.isButton && data.label.isNotEmpty) {
          buttonLabels.add(data.label);
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      // The non-deprecated `rootPipelineOwner` has no semantics owner in a widget
      // test — it lives on the view's pipeline owner, which is what this
      // deprecated accessor returns.
      // ignore: deprecated_member_use
      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

      expect(
        buttonLabels,
        containsAll(<String>['Sources', 'Privacy', 'AI agents']),
        reason: 'each tappable link must be its own labelled button',
      );
      // Exactly three: when a link is the last span in a paragraph, an
      // uncontained Semantics annotation merges upward and turns the whole
      // sentence into one button — announced as a button, tappable anywhere.
      expect(
        buttonLabels,
        hasLength(3),
        reason: 'only the links should be exposed as buttons, got $buttonLabels',
      );

      handle.dispose();
    });
  });
}
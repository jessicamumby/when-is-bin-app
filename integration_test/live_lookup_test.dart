import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:when_is_bin_app/core/app_config.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/home_screen.dart';
import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

/// Live end-to-end lookup against the real WhenIsBins API.
///
/// Requires network access and respects anonymous rate limits (this performs
/// one address discovery + one lookup submission). Not part of the normal
/// `flutter test` suite — run explicitly with:
///   `flutter test integration_test/live_lookup_test.dart -d <device>`
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 400));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live postcode -> address -> schedule journey', (tester) async {
    await dotenv.load();
    final prefs = await SharedPreferences.getInstance();
    final api = WhenIsBinsApi(
      client: http.Client(),
      baseUrl: AppConfig.baseUrl,
      token: AppConfig.apiToken,
    );
    final notificationService = NotificationService();
    await notificationService.init();

    final lookupProvider = LookupProvider(api: api);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WhenIsBinsApi>.value(value: api),
          Provider<NotificationService>.value(value: notificationService),
          ChangeNotifierProvider<LookupProvider>.value(value: lookupProvider),
          ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Enter the postcode and submit.
    await tester.enterText(find.byType(TextField), 'CB4 2HX');
    await tester.tap(find.text('Find my bin day'));
    await tester.pump();

    // 2. Wait for the real address lookup to resolve to the select screen.
    await pumpUntil(
      tester,
      find.textContaining('Select your address'),
      timeout: const Duration(seconds: 30),
    );

    // 3. Tap the first address candidate, which submits a lookup and polls.
    final candidate = find.textContaining('Twickenham Court').first;
    expect(candidate, findsOneWidget);
    // ignore: avoid_print
    print('DEBUG: candidate label = ${tester.widget<Text>(candidate).data}');
    await tester.tap(candidate);
    await tester.pump();

    // 4. Wait for the lookup to settle and the schedule screen to appear.
    //    Real council lookups can take tens of seconds; surface any failure.
    final end = DateTime.now().add(const Duration(seconds: 150));
    var reached = false;
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Your bin days').evaluate().isNotEmpty) {
        reached = true;
        break;
      }
      if (lookupProvider.error != null) {
        // ignore: avoid_print
        print('DEBUG: lookup error -> ${lookupProvider.error}');
        fail('Live lookup failed: ${lookupProvider.error}');
      }
    }
    expect(reached, isTrue,
        reason: 'Schedule screen did not appear within 150s; '
            'postcode=${lookupProvider.postcode}, '
            'loading=${lookupProvider.isLoading}, '
            'error=${lookupProvider.error}');
    await tester.pump();

    // 5. The next-collection card should render with a real date.
    expect(find.textContaining('Next collection'), findsOneWidget);
    expect(find.textContaining('Put out:'), findsOneWidget);

    final putOut = tester.widget<Text>(find.textContaining('Put out:')).data;
    expect(putOut, isNotNull);
    // ignore: avoid_print
    print('LIVE LOOKUP OK — next collection: $putOut');
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/core/theme.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/screens/about_screen.dart';
import 'package:when_is_bin_app/screens/settings_screen.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';

import '../fakes/fake_notification_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app(
    ThemeData theme, {
    Map<String, Object>? prefs,
    FakeNotificationScheduler? notifications,
  }) async {
    SharedPreferences.setMockInitialValues(prefs ?? {});
    final settings = SettingsProvider(await SharedPreferences.getInstance());
    return MultiProvider(
      providers: [
        Provider<ReminderSyncService>.value(
          value: ReminderSyncService(
            notifications: notifications ?? FakeNotificationScheduler(),
          ),
        ),
        ChangeNotifierProvider.value(value: settings),
      ],
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

  testWidgets('moves the reminders already scheduled to the new time', (
    tester,
  ) async {
    // The reminders on the device were built for the old time; changing it
    // must move them now, not at some later launch.
    final next = DateTime.now().add(const Duration(days: 3));
    final nextIso =
        '${next.year}-${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
    final notifications = FakeNotificationScheduler();
    await tester.pumpWidget(
      await app(
        AppTheme.light,
        notifications: notifications,
        prefs: {
          'reminder_time': 'evening',
          'reminders_enabled': true,
          'saved_address': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
          'saved_property_id': 'p:4c5ee6c2f2c7c959',
          'saved_schedule': jsonEncode({
            'property_id': 'p:4c5ee6c2f2c7c959',
            'address_match': 'exact',
            'collections': [
              {
                'name': 'Black bin',
                'waste_type': 'refuse',
                'dates': [nextIso],
              },
            ],
          }),
        },
      ),
    );

    await tester.tap(find.text('Morning before (9:00am)'));
    await tester.pump();

    expect(notifications.pending, hasLength(1));
    expect(notifications.pending.single.fireAt.hour, 9);
  });

  testWidgets('changing the time schedules nothing when reminders are off', (
    tester,
  ) async {
    final notifications = FakeNotificationScheduler();
    await tester.pumpWidget(
      await app(AppTheme.light, notifications: notifications),
    );

    await tester.tap(find.text('Morning before (9:00am)'));
    await tester.pump();

    expect(notifications.scheduled, isEmpty);
  });
}

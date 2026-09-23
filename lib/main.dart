import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'providers/lookup_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/reminder_sync_service.dart';
import 'services/when_is_bins_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final prefs = await SharedPreferences.getInstance();
  final api = WhenIsBinsApi(
    client: http.Client(),
    baseUrl: AppConfig.baseUrl,
    token: AppConfig.apiToken,
  );
  final notificationService = NotificationService();
  await notificationService.init();

  final settings = SettingsProvider(prefs);
  final reminderSync = ReminderSyncService(notifications: notificationService);

  // Reminders outlive the schedule they came from, so re-derive them on every
  // launch: a schedule that has moved on, or a switch the user turned off
  // before killing the app, takes effect without waiting for another lookup.
  try {
    await reminderSync.sync(
      schedule: settings.savedSchedule,
      enabled: settings.remindersEnabled,
      reminderTime: settings.reminderTime,
    );
  } catch (_) {
    // A notification failure must never stop the app from starting.
    debugPrint('Reminder re-sync failed on launch.');
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<WhenIsBinsApi>.value(value: api),
        Provider<NotificationService>.value(value: notificationService),
        Provider<ReminderSyncService>.value(value: reminderSync),
        ChangeNotifierProvider(
          create: (_) => LookupProvider(api: api),
        ),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const WhenIsBinApp(),
    ),
  );
}

class WhenIsBinApp extends StatelessWidget {
  const WhenIsBinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'When is bin day',
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}

import 'dart:async';

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
import 'screens/onboarding_screen.dart';
import 'screens/schedule_screen.dart';
import 'services/notification_service.dart';
import 'services/reminder_sync_service.dart';
import 'services/schedule_refresh_service.dart';
import 'services/timeout_http_client.dart';
import 'services/when_is_bins_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final prefs = await SharedPreferences.getInstance();
  final api = WhenIsBinsApi(
    // Nothing in package:http times out by default: without this a hung
    // connection leaves the app loading for ever.
    client: TimeoutHttpClient(http.Client()),
    baseUrl: AppConfig.baseUrl,
    token: AppConfig.apiToken,
  );
  final notificationService = NotificationService();
  await notificationService.init();

  final settings = SettingsProvider(prefs);
  final reminderSync = ReminderSyncService(notifications: notificationService);
  final scheduleRefresh = ScheduleRefreshService(api: api);
  final lookup = LookupProvider(api: api);

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
          create: (_) => lookup,
        ),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const WhenIsBinApp(),
    ),
  );

  // The stored schedule is re-checked after the first frame, so a collection
  // day the council has moved reaches the user without another lookup — and a
  // slow network never delays the app starting.
  unawaited(
    _recheckSavedSchedule(
      refresh: scheduleRefresh,
      settings: settings,
      reminderSync: reminderSync,
      lookup: lookup,
    ),
  );
}

/// Re-check the stored schedule and, when the council has changed it, save it,
/// re-derive the reminders from it and put it on screen.
Future<void> _recheckSavedSchedule({
  required ScheduleRefreshService refresh,
  required SettingsProvider settings,
  required ReminderSyncService reminderSync,
  required LookupProvider lookup,
}) async {
  final propertyToken = settings.savedPropertyId;
  final cached = settings.savedSchedule;
  if (propertyToken == null || cached == null) return;
  try {
    final result = await refresh.refresh(
      propertyToken: propertyToken,
      cached: cached,
      etag: settings.savedScheduleEtag,
    );
    final updated = result.schedule;
    if (!result.isUpdated || updated == null) return;
    await settings.saveSchedule(updated, etag: result.etag);
    await reminderSync.sync(
      schedule: updated,
      enabled: settings.remindersEnabled,
      reminderTime: settings.reminderTime,
    );
    lookup.restoreSchedule(updated);
  } catch (_) {
    // A failed re-check must never stop the app working from the cached copy.
    debugPrint('Schedule re-check failed on launch.');
  }
}

class WhenIsBinApp extends StatefulWidget {
  const WhenIsBinApp({super.key});

  @override
  State<WhenIsBinApp> createState() => _WhenIsBinAppState();
}

class _WhenIsBinAppState extends State<WhenIsBinApp> {
  @override
  void initState() {
    super.initState();
    // A saved address carries a persisted schedule, so hydrate it straight
    // away — whichever screen the app opens on needs it, not just the
    // search screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      if (settings.savedAddress == null) return;
      context.read<LookupProvider>().restoreSchedule(settings.savedSchedule);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'When is bin day',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The app mirrors the light whenisbins.com design system, so it does not
      // follow the phone into dark mode: a dark-mode device must not repaint
      // the main screens dark while onboarding stays light. Pinning the mode
      // here fixes it at the root, for every route, rather than wrapping each
      // screen in its own light theme.
      themeMode: ThemeMode.light,
      // An onboarded user who still has their saved address sees their bin
      // days directly — they've already found their bin day, so the search
      // form would be noise. Clearing the saved address (from Settings)
      // falls back to the search screen, which starts the journey again.
      home: settings.isOnboarded && settings.savedAddress != null
          ? const ScheduleScreen()
          : settings.isOnboarded
              ? const HomeScreen()
              : const OnboardingScreen(),
    );
  }
}
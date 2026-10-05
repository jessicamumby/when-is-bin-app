import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'providers/lookup_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/schedule_screen.dart';
import 'services/background_refresh.dart';
import 'services/notification_service.dart';
import 'services/reminder_scheduler.dart';
import 'services/reminder_sync_service.dart';
import 'services/schedule_recheck_service.dart';
import 'services/schedule_refresh_service.dart';
import 'services/when_is_bins_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final prefs = await SharedPreferences.getInstance();
  final api = WhenIsBinsApi.fromConfig();
  final notificationService = NotificationService();
  await notificationService.init();

  final settings = SettingsProvider(prefs);
  final reminderSync = ReminderSyncService(notifications: notificationService);
  final recheck = ScheduleRecheckService(
    refresh: ScheduleRefreshService(api: api),
    reminderSync: reminderSync,
  );
  final lookup = LookupProvider(api: api);

  // While the app is running, the background task hands its re-check to this
  // isolate, so only one isolate ever writes the schedule and the reminders.
  ForegroundRecheck.serve(
    () => _recheckSavedSchedule(
      recheck: recheck,
      settings: settings,
      lookup: lookup,
    ),
  );

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
        Provider<ScheduleRecheckService>.value(value: recheck),
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
  // slow network never delays the app starting. A launch always checks; the
  // resume and background checks are rationed.
  unawaited(
    _recheckSavedSchedule(
      recheck: recheck,
      settings: settings,
      lookup: lookup,
      force: true,
    ),
  );

  // For the user who relies on the reminders and rarely opens the app.
  unawaited(
    BackgroundRefresh.schedule().catchError((Object _) {
      debugPrint('Background refresh could not be scheduled.');
    }),
  );
}

/// Re-check the stored schedule and, when the council has changed it, put the
/// new dates on screen. Saving them and moving the reminders is the
/// [ScheduleRecheckService]'s job.
Future<RecheckOutcome> _recheckSavedSchedule({
  required ScheduleRecheckService recheck,
  required SettingsProvider settings,
  required LookupProvider lookup,
  bool force = false,
}) async {
  try {
    final outcome = await recheck.recheck(settings, force: force);
    if (outcome is ScheduleUpdated) lookup.restoreSchedule(outcome.schedule);
    return outcome;
  } catch (_) {
    // A failed re-check must never stop the app working from the cached copy.
    debugPrint('Schedule re-check failed.');
    return const RecheckFailed();
  }
}

class WhenIsBinApp extends StatefulWidget {
  const WhenIsBinApp({super.key});

  @override
  State<WhenIsBinApp> createState() => _WhenIsBinAppState();
}

class _WhenIsBinAppState extends State<WhenIsBinApp>
    with WidgetsBindingObserver {
  late final SettingsProvider _settings;

  /// What the reminders on the device were last derived from.
  late String _remindersSyncedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // main() has already synced the reminders for the settings as they stand.
    _settings = context.read<SettingsProvider>();
    _remindersSyncedFor = _reminderInputs();
    _settings.addListener(_onSettingsChanged);
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
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Everything the reminders are derived from, as one comparable value.
  String _reminderInputs() {
    final schedule = _settings.savedSchedule;
    return jsonEncode({
      'enabled': _settings.remindersEnabled,
      'time': _settings.reminderTime.name,
      'provisional': schedule?.provisional,
      'collections': schedule?.collections.map((c) => c.toJson()).toList(),
    });
  }

  /// Keep the reminders on the device in step with what is saved.
  ///
  /// Removing the address, saving a new one, changing the reminder time and
  /// flipping the switch each happen on a different screen; syncing here
  /// means none of them can leave the device reminding about an address the
  /// user has removed, or silent for the one they have just set.
  void _onSettingsChanged() {
    final inputs = _reminderInputs();
    if (inputs == _remindersSyncedFor) return;
    _remindersSyncedFor = inputs;
    _syncReminders('Reminder re-sync failed after a settings change.');
  }

  void _syncReminders(String failure) {
    unawaited(
      context
          .read<ReminderSyncService>()
          .sync(
            schedule: _settings.savedSchedule,
            enabled: _settings.remindersEnabled,
            reminderTime: _settings.reminderTime,
          )
          .catchError((Object _) {
            debugPrint(failure);
            return const <Reminder>[];
          }),
    );
  }

  /// Re-derive the reminders whenever the app comes back to the foreground,
  /// then re-check the schedule if it is due.
  ///
  /// iOS silently drops reminders scheduled before the user has allowed
  /// notifications, and onboarding stops waiting for the permission prompt
  /// after a few seconds, so a user who reads the prompt before tapping Allow
  /// ends up with none. Answering the prompt (or allowing notifications later
  /// in the Settings app) resumes the app, and iOS rarely cold-starts a
  /// suspended app, so this is the moment to put the reminders back rather
  /// than waiting for the next launch. For the same reason the launch-time
  /// re-check of the schedule would rarely run on its own.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    final recheck = context.read<ScheduleRecheckService>();
    final lookup = context.read<LookupProvider>();
    // The background task may have saved a moved schedule from its own
    // isolate, which this isolate's cache cannot see. Reload before syncing,
    // or the sync would bring the old dates' reminders back.
    try {
      if (await _settings.reload() && _settings.savedAddress != null) {
        lookup.restoreSchedule(_settings.savedSchedule);
      }
    } catch (_) {
      debugPrint('Settings reload failed on resume.');
    }
    if (!mounted) return;
    _syncReminders('Reminder re-sync failed on resume.');
    await _recheckSavedSchedule(
      recheck: recheck,
      settings: _settings,
      lookup: lookup,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'When Is Bins',
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
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../providers/settings_provider.dart';
import 'notification_service.dart';
import 'reminder_sync_service.dart';
import 'schedule_recheck_service.dart';
import 'schedule_refresh_service.dart';
import 'when_is_bins_api.dart';

/// The periodic background re-check of the saved schedule.
///
/// Android runs it through WorkManager about once a day, whenever there is a
/// network, whether or not the app has been opened. iOS runs it as a
/// BGAppRefreshTask only when iOS chooses to: the interval asked for is a
/// floor, not a promise, and iOS rations background time by how often the app
/// is used. On iOS this narrows the gap for someone who never opens the app;
/// it does not close it.
class BackgroundRefresh {
  BackgroundRefresh._();

  /// The task's single identifier. On Android it is the WorkManager unique
  /// name. On iOS it is the BGTaskScheduler identifier, so the same string
  /// must also be listed under `BGTaskSchedulerPermittedIdentifiers` in
  /// Info.plist and registered in AppDelegate.swift (release_config_test pins
  /// all three).
  static const taskId = 'com.jessicamumby.whenIsBinApp.scheduleRefresh';

  /// How often Android runs the task. The re-check itself is still limited to
  /// one per [ScheduleRecheckService.recheckInterval], so a run soon after the
  /// app has checked costs no request.
  static const frequency = Duration(hours: 24);

  /// Register the task with the OS. Safe to call on every launch.
  static Future<void> schedule() async {
    final workmanager = Workmanager();
    await workmanager.initialize(backgroundRefreshDispatcher);
    await workmanager.registerPeriodicTask(
      taskId,
      taskId,
      frequency: frequency,
      // The app has just checked on launch, so an earlier run would only be
      // turned away by the recheck interval. On iOS this is the
      // earliestBeginDate of the first request.
      initialDelay: ScheduleRecheckService.recheckInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      // `update` keeps the original enqueue time, so registering again on
      // every launch never pushes the next run back.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}

/// Hands the background task's work to the app when the app is running.
///
/// The background task runs in its own isolate, with its own SharedPreferences
/// cache. If it re-checked while the app's isolate was alive too, each would
/// re-derive the reminders from its own copy of the schedule and whichever
/// synced last would win, possibly with the old dates. So when the app is
/// running, the background task asks it to do the re-check, and there is only
/// ever one writer. [IsolateNameServer] is per process, and both isolates live
/// in the app's process.
class ForegroundRecheck {
  ForegroundRecheck._();

  static const portName = 'when_is_bins.schedule_recheck';

  static const _accepted = 'accepted';
  static const _done = 'done';

  /// Serve re-check requests from the background task in the app's isolate.
  ///
  /// Replaces any earlier registration: a port left by an isolate that has
  /// since gone would otherwise answer nothing.
  static ReceivePort serve(Future<RecheckOutcome> Function() recheck) {
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    port.listen((message) async {
      if (message is! SendPort) return;
      message.send(_accepted);
      try {
        await recheck();
      } catch (_) {
        debugPrint('Schedule re-check failed for the background task.');
      }
      message.send(_done);
    });
    return port;
  }

  /// Ask the app's isolate, if one is running, to do the re-check. True when
  /// the app took it on.
  ///
  /// An app that does not accept within [ackTimeout] is treated as gone
  /// (Android keeps the process, and the name, after the activity is
  /// destroyed), and the caller re-checks itself. The name is left in place in
  /// case the app was only slow: it is replaced on the next launch anyway, and
  /// the app reloads storage when it resumes. An app that accepted is left to
  /// finish even past [doneTimeout], because a second, headless writer is
  /// exactly what this exists to prevent.
  ///
  /// The two timeouts together stay inside the roughly 30 seconds iOS gives a
  /// background refresh.
  static Future<bool> handOff({
    Duration ackTimeout = const Duration(seconds: 5),
    Duration doneTimeout = const Duration(seconds: 20),
  }) async {
    final app = IsolateNameServer.lookupPortByName(portName);
    if (app == null) return false;

    final reply = ReceivePort();
    final accepted = Completer<void>();
    final done = Completer<void>();
    reply.listen((message) {
      if (message == _accepted && !accepted.isCompleted) accepted.complete();
      if (message == _done && !done.isCompleted) done.complete();
    });

    try {
      app.send(reply.sendPort);
      await accepted.future.timeout(ackTimeout);
    } on TimeoutException {
      reply.close();
      return false;
    }

    try {
      await done.future.timeout(doneTimeout);
    } on TimeoutException {
      // Still working: leave it to finish.
    }
    reply.close();
    return true;
  }
}

/// One background run: hand the re-check to the app if it is running,
/// otherwise do it here.
///
/// Always reports success. A failure asks WorkManager for a retry, which
/// backs off from 30 seconds: against a rate limit that is a retry storm, and
/// the next daily run is retry enough.
Future<bool> runBackgroundRecheck({
  Future<bool> Function() handOff = ForegroundRecheck.handOff,
  Future<RecheckOutcome> Function() headless = _headlessRecheck,
}) async {
  try {
    if (await handOff()) return true;
    await headless();
  } catch (_) {
    debugPrint('Background schedule re-check failed.');
  }
  return true;
}

/// The re-check with nothing of the app's running: every dependency is built
/// fresh in this isolate, as main() builds them.
Future<RecheckOutcome> _headlessRecheck() async {
  await dotenv.load();
  final prefs = await SharedPreferences.getInstance();
  // Pins reminders to Europe/London, exactly as on launch.
  final notifications = NotificationService();
  await notifications.init();
  final recheck = ScheduleRecheckService(
    refresh: ScheduleRefreshService(api: WhenIsBinsApi.fromConfig()),
    reminderSync: ReminderSyncService(notifications: notifications),
  );
  return recheck.recheck(SettingsProvider(prefs));
}

/// The entry point the OS starts the background isolate with.
@pragma('vm:entry-point')
void backgroundRefreshDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != BackgroundRefresh.taskId &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return runBackgroundRecheck();
  });
}

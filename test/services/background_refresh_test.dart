import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/services/background_refresh.dart';
import 'package:when_is_bin_app/services/schedule_recheck_service.dart';
import 'package:workmanager/workmanager.dart';

/// Records what the app asked the OS scheduler for, instead of reaching
/// WorkManager or BGTaskScheduler.
class FakeWorkmanagerPlatform extends WorkmanagerPlatform {
  Function? dispatcher;
  final periodic = <Map<String, Object?>>[];

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async {
    dispatcher = callbackDispatcher;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    periodic.add({
      'uniqueName': uniqueName,
      'taskName': taskName,
      'frequency': frequency,
      'initialDelay': initialDelay,
      'networkType': constraints?.networkType,
      'existingWorkPolicy': existingWorkPolicy,
      'foregroundServiceConfig': foregroundServiceConfig,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundRefresh.schedule', () {
    late FakeWorkmanagerPlatform platform;

    // The Workmanager singleton installs the host platform's implementation
    // the first time it is built, so build it before the fake goes in.
    setUpAll(Workmanager.new);

    setUp(() {
      platform = FakeWorkmanagerPlatform();
      WorkmanagerPlatform.instance = platform;
    });

    test('registers one daily task that needs a network', () async {
      await BackgroundRefresh.schedule();

      expect(platform.dispatcher, same(backgroundRefreshDispatcher));
      expect(platform.periodic, hasLength(1));
      final task = platform.periodic.single;
      // iOS hands the handler the BGTaskScheduler identifier, so the unique
      // name and the task name must be the same string.
      expect(task['uniqueName'], BackgroundRefresh.taskId);
      expect(task['taskName'], BackgroundRefresh.taskId);
      expect(task['frequency'], const Duration(hours: 24));
      expect(task['networkType'], NetworkType.connected);
      // Never a foreground service: no persistent notification, and no Play
      // Console foreground-service declaration.
      expect(task['foregroundServiceConfig'], isNull);
    });

    test('re-registering on every launch does not restart the period', () {
      // `update` keeps the original enqueue time; `replace` would push the
      // next run back a day every time the app opens.
      return BackgroundRefresh.schedule().then((_) {
        expect(
          platform.periodic.single['existingWorkPolicy'],
          ExistingPeriodicWorkPolicy.update,
        );
      });
    });

    test('waits a recheck interval before the first background run', () async {
      // The app has just checked on launch, so an immediate background run
      // would only be refused by the interval anyway.
      await BackgroundRefresh.schedule();

      expect(
        platform.periodic.single['initialDelay'],
        ScheduleRecheckService.recheckInterval,
      );
    });

    test('the task id is the iOS bundle id plus a task name', () {
      // BGTaskScheduler identifiers are conventionally prefixed with the
      // bundle id; release_config_test pins the Info.plist and AppDelegate
      // copies of this same string.
      expect(
        BackgroundRefresh.taskId,
        startsWith('com.jessicamumby.whenIsBinApp.'),
      );
    });
  });

  group('ForegroundRecheck', () {
    tearDown(() {
      IsolateNameServer.removePortNameMapping(ForegroundRecheck.portName);
    });

    test('nothing is handed off when the app is not running', () async {
      final tookIt = await ForegroundRecheck.handOff();

      expect(tookIt, isFalse);
    });

    test('a running app does the re-check itself', () async {
      var appRechecks = 0;
      final port = ForegroundRecheck.serve(() async {
        appRechecks++;
        return const ScheduleStillCurrent();
      });
      addTearDown(port.close);

      final tookIt = await ForegroundRecheck.handOff();

      expect(tookIt, isTrue);
      expect(appRechecks, 1);
    });

    test('waits for the app to finish before reporting back', () async {
      final finish = Completer<RecheckOutcome>();
      final port = ForegroundRecheck.serve(() => finish.future);
      addTearDown(port.close);

      var reported = false;
      final handOff = ForegroundRecheck.handOff().then((tookIt) {
        reported = true;
        return tookIt;
      });
      await pumpEventQueue();
      expect(reported, isFalse);

      finish.complete(const ScheduleStillCurrent());

      expect(await handOff, isTrue);
    });

    test('an app that has gone is not waited on for long', () async {
      // Android keeps the process (and the name registration) after the
      // activity is destroyed, so the port can outlive the isolate behind it.
      final dead = ReceivePort()..close();
      IsolateNameServer.registerPortWithName(
        dead.sendPort,
        ForegroundRecheck.portName,
      );

      final tookIt = await ForegroundRecheck.handOff(
        ackTimeout: const Duration(milliseconds: 50),
      );

      expect(tookIt, isFalse);
    });

    test('an app that accepted but is slow is not doubled up', () async {
      // Two writers is what the hand-off exists to prevent, so a slow app is
      // left to finish rather than raced by a headless re-check.
      final port = ForegroundRecheck.serve(
        () => Completer<RecheckOutcome>().future,
      );
      addTearDown(port.close);

      final tookIt = await ForegroundRecheck.handOff(
        doneTimeout: const Duration(milliseconds: 50),
      );

      expect(tookIt, isTrue);
    });

    test('a re-check that throws in the app still answers', () async {
      final port = ForegroundRecheck.serve(() async => throw StateError('x'));
      addTearDown(port.close);

      expect(await ForegroundRecheck.handOff(), isTrue);
    });

    test('serving again replaces the old registration', () async {
      var first = 0;
      var second = 0;
      final old = ForegroundRecheck.serve(() async {
        first++;
        return const ScheduleStillCurrent();
      });
      addTearDown(old.close);
      final current = ForegroundRecheck.serve(() async {
        second++;
        return const ScheduleStillCurrent();
      });
      addTearDown(current.close);

      await ForegroundRecheck.handOff();

      expect(first, 0);
      expect(second, 1);
    });
  });

  group('runBackgroundRecheck', () {
    test('leaves the work to a running app', () async {
      var headless = 0;

      final ok = await runBackgroundRecheck(
        handOff: () async => true,
        headless: () async {
          headless++;
          return const ScheduleStillCurrent();
        },
      );

      expect(ok, isTrue);
      expect(headless, 0);
    });

    test('re-checks headlessly when the app is not running', () async {
      var headless = 0;

      final ok = await runBackgroundRecheck(
        handOff: () async => false,
        headless: () async {
          headless++;
          return const ScheduleStillCurrent();
        },
      );

      expect(ok, isTrue);
      expect(headless, 1);
    });

    test('never asks the OS for a retry', () async {
      // A WorkManager retry backs off from 30 seconds; against a rate limit
      // that is a retry storm. The next daily run is the retry.
      final failed = await runBackgroundRecheck(
        handOff: () async => false,
        headless: () async => const RecheckFailed(),
      );
      final threw = await runBackgroundRecheck(
        handOff: () async => false,
        headless: () async => throw StateError('plugin missing'),
      );

      expect(failed, isTrue);
      expect(threw, isTrue);
    });
  });
}

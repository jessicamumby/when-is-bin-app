import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:when_is_bin_app/main.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/notification_service.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';
import 'package:when_is_bin_app/services/reminder_sync_service.dart';
import 'package:when_is_bin_app/services/schedule_recheck_service.dart';
import 'package:when_is_bin_app/services/schedule_refresh_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../verify/support.dart';

/// Marketing capture drive: the real first-run journey (postcode, address,
/// lookup, reminder choice, bin days) with made-up data, for ads and store
/// screenshots. Capture scaffolding only, like the verify drives: the app
/// never imports it and CI does not run it.
///
/// No request reaches the WhenIsBins API. The app's own [WhenIsBinsApi] client
/// talks to a [MockClient] that answers with an invented council, street and
/// alternate-week schedule, so nothing on screen is a real home and the drive
/// cannot spend the per-IP allowance. Everything else (parsing, providers,
/// screens, reminder scheduling) is the shipping code.
///
/// Run on a fresh install (uninstall first, so onboarding shows):
///   RUN_DIR=... flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/capture/ad_capture_test.dart -d UDID \
///     --keep-app-running
/// Answer the notification prompt with the verify skill's
/// `tap_system_button.sh UDID Allow`. The drive ends by scheduling one real
/// reminder notification [_demoDelay] ahead, so the host can terminate the app
/// and screenshot the banner on the home screen.
const _postcode = 'AB1 2CD';
const _street = 'Kerbside Close, Anytown, AB1 2CD';
const _pick = '14 $_street';
const _demoDelay = Duration(seconds: 40);

/// The next collection, as yyyy-MM-dd. Pin it for ads, so a capture does not
/// go stale the week it is taken: `--dart-define=CAPTURE_NEXT=2026-11-19`.
/// Empty means the next Thursday at least three days away.
const _captureNext = String.fromEnvironment('CAPTURE_NEXT');

/// Pauses between steps, so a screen recording reads at human speed.
const _beat = Duration(milliseconds: 1400);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ad capture: first run with made-up data', (tester) async {
    // A capture is for the store and ads, not for telling builds apart.
    WidgetsApp.debugAllowBannerOverride = false;
    await dotenv.load();

    final days = _alternateWeeks();
    final api = WhenIsBinsApi(
      client: MockClient(_fakeApi(days)),
      baseUrl: 'https://capture.invalid/v1',
      token: null,
    );
    final prefs = await SharedPreferences.getInstance();
    final notifications = NotificationService();
    await notifications.init();
    final settings = SettingsProvider(prefs);
    final reminderSync = ReminderSyncService(notifications: notifications);
    final recheck = ScheduleRecheckService(
      refresh: ScheduleRefreshService(api: api),
      reminderSync: reminderSync,
    );
    final lookup = LookupProvider(api: api);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<WhenIsBinsApi>.value(value: api),
          Provider<NotificationService>.value(value: notifications),
          Provider<ReminderSyncService>.value(value: reminderSync),
          Provider<ScheduleRecheckService>.value(value: recheck),
          ChangeNotifierProvider.value(value: lookup),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: const WhenIsBinApp(),
      ),
    );

    await pumpUntil(
      tester,
      find.text('Find your bin day'),
      reason: 'PRECONDITION: onboarding is not showing. Uninstall the app '
          'and drive again.',
    );
    await tester.pumpAndSettle();
    await shot(binding, tester, 'ad-01-onboarding');
    mark('AD ready');
    await _hold(tester, const Duration(seconds: 4));

    final field = inOnboarding(find.widgetWithText(TextField, 'Postcode'));
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 1; i <= _postcode.length; i++) {
      await tester.enterText(field, _postcode.substring(0, i));
      await tester.pump(const Duration(milliseconds: 170));
      await shot(binding, tester, 'ad-02-postcode-$i');
    }
    await _hold(tester, const Duration(milliseconds: 600));
    await shot(binding, tester, 'ad-02-postcode');
    await tester.tap(inOnboarding(find.text('Find my bin day')));
    mark('action tapped "Find my bin day" with $_postcode');
    await tester.pump(const Duration(milliseconds: 200));
    await shot(binding, tester, 'ad-02b-postcode-loading');

    await pumpUntil(tester, find.text('Select your address'));
    await tester.pumpAndSettle();
    await shot(binding, tester, 'ad-03-address-picker');
    await _hold(tester, _beat);

    await tester.tap(find.text(_pick));
    mark('action picked "$_pick"');
    await tester.pump(const Duration(milliseconds: 400));
    await shot(binding, tester, 'ad-04-finding');

    await pumpUntil(
      tester,
      find.text('When should we remind you?'),
      timeout: const Duration(seconds: 20),
    );
    await tester.pumpAndSettle();
    await shot(binding, tester, 'ad-05-reminder-step');
    await _hold(tester, _beat);
    await tester.tap(find.text('Morning before (9:00am)'));
    await _hold(tester, const Duration(milliseconds: 700));
    await tester.tap(find.text('Evening before (7:00pm)'));
    await _hold(tester, const Duration(milliseconds: 900));
    await shot(binding, tester, 'ad-05b-evening-chosen');

    await tester.tap(find.text('Turn on reminders'));
    mark('action tapped "Turn on reminders"');
    await pumpUntil(
      tester,
      find.text('Next collection'),
      timeout: const Duration(seconds: 40),
    );
    await tester.pumpAndSettle();
    await _hold(tester, _beat);
    await shot(binding, tester, 'ad-06-bin-days');
    mark('state bin days: next ${days.next} reminders_enabled='
        '${settings.remindersEnabled} time=${settings.reminderTime.name}');
    await _hold(tester, const Duration(seconds: 2));

    final scroller = find.byType(SingleChildScrollView).last;
    await tester.drag(scroller, const Offset(0, -420));
    await tester.pumpAndSettle();
    await _hold(tester, _beat);
    await shot(binding, tester, 'ad-07-reminders-on');
    await tester.drag(scroller, const Offset(0, -600));
    await tester.pumpAndSettle();
    await _hold(tester, _beat);
    await shot(binding, tester, 'ad-08-calendar');
    await tester.drag(scroller, const Offset(0, 1200));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _hold(tester, _beat);
    await shot(binding, tester, 'ad-09-settings');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _hold(tester, _beat);
    mark('AD flow done');

    // One reminder built by the shipping code, brought forward so the banner
    // can be captured now instead of at 7pm the day before. Reminders are
    // wall-clock times in Europe/London (tz.local after init), whatever zone
    // the simulator runs in, so the fire time is taken from that clock.
    final london = tz.TZDateTime.now(tz.local).add(_demoDelay);
    final fireAt = DateTime(london.year, london.month, london.day,
        london.hour, london.minute, london.second);
    await notifications.scheduleReminders([
      Reminder(
        collectionDate: DateTime.parse(days.next),
        fireAt: fireAt,
        binNames: const ['Blue bin (recycling)', 'Green bin (garden)'],
      ),
    ]);
    final pending =
        await FlutterLocalNotificationsPlugin().pendingNotificationRequests();
    for (final p in pending) {
      mark('pending id=${p.id} title="${p.title}" body="${p.body}"');
    }
    mark('AD demo notification at ${DateFormat('HH:mm:ss').format(fireAt)}');
  });
}

Future<void> _hold(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Collection dates in ISO form: recycling and garden on [_captureNext] (or
/// the next Thursday at least three days away), rubbish the week after,
/// alternating.
({String next, String after, String third, String fourth}) _alternateWeeks() {
  var day = DateTime.now().add(const Duration(days: 3));
  while (day.weekday != DateTime.thursday) {
    day = day.add(const Duration(days: 1));
  }
  if (_captureNext.isNotEmpty) day = DateTime.parse(_captureNext);
  final iso = DateFormat('yyyy-MM-dd');
  String week(int n) => iso.format(day.add(Duration(days: 7 * n)));
  return (next: week(0), after: week(1), third: week(2), fourth: week(3));
}

MockClientHandler _fakeApi(
  ({String next, String after, String third, String fourth}) days,
) {
  const council = {
    'id': 'capture-council',
    'name': 'Anytown Council',
    'expected_wait_seconds': 5,
  };
  final weekday = DateFormat('EEEE');
  Map<String, dynamic> entry(String date, List<(String, String)> bins) => {
        'date': date,
        'weekday': weekday.format(DateTime.parse(date)),
        'collections': [
          for (final (name, type) in bins) {'name': name, 'waste_type': type},
        ],
      };
  const blue = ('Blue bin (recycling)', 'recycling');
  const green = ('Green bin (garden)', 'garden');
  const black = ('Black bin (rubbish)', 'rubbish');
  final schedule = {
    'property_id': 'p:capture14',
    'address_match': 'exact',
    'council': council,
    'collections': [
      {
        'name': blue.$1,
        'waste_type': blue.$2,
        'dates': [days.next, days.third],
      },
      {
        'name': green.$1,
        'waste_type': green.$2,
        'dates': [days.next, days.third],
      },
      {
        'name': black.$1,
        'waste_type': black.$2,
        'dates': [days.after, days.fourth],
      },
    ],
    'by_date': [
      entry(days.next, [blue, green]),
      entry(days.after, [black]),
      entry(days.third, [blue, green]),
      entry(days.fourth, [black]),
    ],
    'calendar_url': 'https://capture.invalid/calendar/capture14.ics',
  };

  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  return (request) async {
    final path = request.url.path;
    if (path.endsWith('/addresses')) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return json({
        'postcode': _postcode,
        'council': council,
        'required_input': 'property_id',
        'candidates_source': 'council',
        'candidates': [
          for (final n in [8, 10, 12, 14, 16, 18, 20])
            {'id': 'p:capture$n', 'label': '$n $_street'},
        ],
      });
    }
    if (request.method == 'POST' && path.endsWith('/lookups')) {
      return json({
        'id': 'capture-lookup',
        'status': 'running',
        'council': council,
        'expected_wait_seconds': 5,
      });
    }
    if (path.endsWith('/wait')) {
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      return json({
        'id': 'capture-lookup',
        'status': 'done',
        'council': council,
        'result': schedule,
      });
    }
    if (path.contains('/schedules/')) return http.Response('', 304);
    return http.Response('{"detail":"not in the capture fixture"}', 404);
  };
}

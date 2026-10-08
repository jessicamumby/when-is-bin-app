import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/main.dart' as app;
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';

import 'support.dart';

/// verify-when-is-bin features `bg-stamp` and `bg-resume`, plus the bin-days
/// screen as it ships (the collection after next, the reminder caveat, the
/// calendar card, the About credit).
///
/// Calls the live API: every re-check is one `GET /schedules/{token}`. The
/// saved property is Cambridge Central Library (`p:8ccd92739644bc77`, CB2
/// 3QD), a public building with no household collection, so the API answers
/// `404 no_schedule`. The app records that as a completed check (the cached
/// schedule stands), which is what makes `schedule_checked_at` a clean probe:
/// it only moves when the API answered. A 429 or a dead network leaves it
/// where it was. The schedule on screen is a fixture (alternate weeks, with a
/// calendar feed), arranged through SettingsProvider as in
/// reminders_switch_after_permission_test.dart.
const _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
const _checkedAtKey = 'schedule_checked_at';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bg-resume: launch always re-checks, a return after 12 hours '
      're-checks, a return within 12 hours does not', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final fixture = SettingsProvider(prefs);
    final iso = DateFormat('yyyy-MM-dd');
    final days = [
      (iso.format(DateTime.now().add(const Duration(days: 3))), 'Black bin'),
      (iso.format(DateTime.now().add(const Duration(days: 10))), 'Blue bin'),
      (iso.format(DateTime.now().add(const Duration(days: 17))), 'Black bin'),
    ];
    final schedule = Schedule(
      propertyId: 'p:8ccd92739644bc77',
      addressMatch: 'exact',
      calendarUrl: 'https://whenisbins.com/verify-fixture.ics',
      collections: [
        for (final (date, bin) in days)
          Collection(name: bin, wasteType: 'rubbish', dates: [date]),
      ],
      byDate: [
        for (final (date, bin) in days)
          ByDateEntry(
            date: date,
            weekday: DateFormat('EEEE').format(DateTime.parse(date)),
            collections: [ByDateCollection(name: bin, wasteType: 'rubbish')],
          ),
      ],
    );
    await fixture.saveAddress(
      address: 'Central Library, Lion Yard (fixture schedule)',
      postcode: 'CB2 3QD',
      propertyId: schedule.propertyId,
    );
    await fixture.saveSchedule(schedule);
    await fixture.setRemindersEnabled(false);
    await fixture.markOnboarded();
    // saveSchedule stamps "now"; start from an old stamp so a fresh one can
    // only come from the launch check.
    final arranged = DateTime.now().toUtc().subtract(const Duration(days: 2));
    await prefs.setString(_checkedAtKey, arranged.toIso8601String());
    mark('arrange fixture schedule for p:8ccd92739644bc77 (Central Library); '
        '$_checkedAtKey=${arranged.toIso8601String()}');

    DateTime? stamp() {
      final raw = prefs.getString(_checkedAtKey);
      return raw == null ? null : DateTime.tryParse(raw);
    }

    /// Waits for the stamp to move past [after]; null if it never does.
    Future<DateTime?> stampAfter(DateTime after, Duration timeout) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        final now = stamp();
        if (now != null && now.isAfter(after)) return now;
      }
      return null;
    }

    // No pumps between the states: while the app is hidden or paused the
    // binding schedules no frames, so a pump there never returns.
    Future<void> backgroundAndReturn() async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    app.main();
    await pumpUntil(
      tester,
      find.text('Next collection'),
      reason: 'PRECONDITION: the app did not open on the bin days.',
    );

    // 1. Cold launch: always checks.
    final launchStamp =
        await stampAfter(arranged, const Duration(seconds: 30));
    mark('state launch check: $_checkedAtKey=${launchStamp?.toIso8601String()}');
    expect(launchStamp, isNotNull,
        reason: 'PRECONDITION: the launch check never completed. A 429 or no '
            'network leaves the stamp alone: run find_postcode_only.sh.');

    await tester.pumpAndSettle();
    final next = DateFormat('EEEE d MMMM yyyy').format(DateTime.parse(days[0].$1));
    final after = DateFormat('EEEE d MMMM yyyy').format(DateTime.parse(days[1].$1));
    mark('state bin days: next "$next" shown=${find.text(next).evaluate().isNotEmpty}; '
        'After that shown=${find.text('After that').evaluate().isNotEmpty}; '
        '"$after" shown=${find.text(after).evaluate().isNotEmpty}; '
        'Blue bin shown=${find.text('Blue bin').evaluate().isNotEmpty}; '
        'reminder caveat shown=${find.textContaining('Reminders follow the dates your council publishes').evaluate().isNotEmpty}');
    await shot(binding, tester, 'e2e-1-bin-days');
    await tester.scrollUntilVisible(find.text('Open calendar feed'), 200);
    await tester.pumpAndSettle();
    mark('state calendar card: Open calendar feed shown=true; Send yourself '
        'the link shown=${find.text('Send yourself the link').evaluate().isNotEmpty}');
    await shot(binding, tester, 'e2e-2-calendar-card');

    // 2. Back after 13 hours: due, so it checks.
    final old = DateTime.now().toUtc().subtract(const Duration(hours: 13));
    await prefs.setString(_checkedAtKey, old.toIso8601String());
    mark('arrange last check 13h ago: $_checkedAtKey=${old.toIso8601String()}');
    await backgroundAndReturn();
    mark('action backgrounded and returned to the app');
    final resumeStamp = await stampAfter(old, const Duration(seconds: 30));
    mark('state resume after 13h: $_checkedAtKey=${resumeStamp?.toIso8601String()}');
    expect(resumeStamp, isNotNull,
        reason: 'BEHAVIOUR: returning after 13 hours did not re-check (or the '
            'API did not answer: check the drive log for a 429).');
    expect(resumeStamp!.isAfter(launchStamp!), isTrue);

    // 3. Straight back again: within 12 hours, so no request.
    await backgroundAndReturn();
    mark('action backgrounded and returned again at once');
    await tester.pump(const Duration(seconds: 8));
    final controlStamp = stamp();
    mark('state resume within 12h: $_checkedAtKey=${controlStamp?.toIso8601String()} '
        '(unchanged=${controlStamp == resumeStamp})');
    expect(controlStamp, resumeStamp,
        reason: 'BEHAVIOUR: a return within 12 hours re-checked anyway');

    // 4. What the user sees.
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.textContaining('Dates last checked: '));
    await tester.pumpAndSettle();
    final line = tester.widget<Text>(find.textContaining('Dates last checked: ')).data;
    final expected = DateFormat('EEEE d MMMM, HH:mm').format(resumeStamp.toLocal());
    mark('state settings "$line" (stored resume check, local: $expected); '
        '"${tester.widget<Text>(find.textContaining('Build ')).data}" '
        '(drive built $_gitSha)');
    await shot(binding, tester, 'e2e-3-settings');

    await tester.tap(find.text('About'));
    await pumpUntil(tester, find.text('Tom Loosemore\u2019s post'));
    await tester.pumpAndSettle();
    mark('state about credit shown='
        '${find.textContaining('Public Digital built WhenIsBins to learn how to respond to AI agents.').evaluate().isNotEmpty}');
    await shot(binding, tester, 'e2e-4-about');
  });
}

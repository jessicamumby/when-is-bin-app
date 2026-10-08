import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/main.dart' as app;
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';

import 'support.dart';

/// verify-when-is-bin feature `set-calendar-copy`.
///
/// Needs no API: the precondition (an onboarded user with a saved schedule
/// that has a calendar feed) is ARRANGED through the app's own
/// SettingsProvider before the app starts, as in
/// reminders_switch_after_permission_test.dart. Runs on iOS and Android.
///
/// Covers the reminder card's published-dates caveat, the calendar card on
/// each platform (iOS: the webcal button; Android: "Send yourself the link"
/// opens the system share sheet, "Copy link" copies the feed), and the About
/// screen crediting Public Digital.
///
/// On Android the share sheet is native, so the host captures it: after the
/// drive prints `VERIFY action tapped Send yourself the link`, take
/// `adb exec-out screencap -p > "$RUN_DIR/cal-2-share-sheet.png"` and press
/// Back (`adb shell input keyevent KEYCODE_BACK`) within [_shareSheetWait].
const _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
const _calendarUrl = 'https://whenisbins.com/verify-fixture.ics';
const _shareSheetWait = Duration(seconds: 20);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('set-calendar-copy: the calendar card, the reminder caveat and '
      'the About credit', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final fixture = SettingsProvider(prefs);
    final fmt = DateFormat('yyyy-MM-dd');
    final dates = [
      fmt.format(DateTime.now().add(const Duration(days: 7))),
      fmt.format(DateTime.now().add(const Duration(days: 14))),
    ];
    final schedule = Schedule(
      propertyId: 'p:verify-fixture',
      addressMatch: 'exact',
      calendarUrl: _calendarUrl,
      collections: [
        Collection(name: 'Black bin', wasteType: 'rubbish', dates: dates),
      ],
      byDate: [
        for (final date in dates)
          ByDateEntry(
            date: date,
            weekday: DateFormat('EEEE').format(DateTime.parse(date)),
            collections: const [
              ByDateCollection(name: 'Black bin', wasteType: 'rubbish'),
            ],
          ),
      ],
    );
    await fixture.saveAddress(
      address: 'Verify fixture (not a real address)',
      postcode: 'ZZ99 9ZZ',
      propertyId: schedule.propertyId,
    );
    await fixture.saveSchedule(schedule);
    await fixture.setRemindersEnabled(false);
    await fixture.markOnboarded();
    mark('arrange fixture schedule with calendar feed $_calendarUrl, '
        'onboarded, platform=${Platform.operatingSystem}');

    // Android screenshots need the Flutter surface rendered to an image.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    app.main();
    await pumpUntil(
      tester,
      find.text('Remind me to put the bins out'),
      reason: 'PRECONDITION: the app did not open on the bin days. Uninstall '
          'it and drive again.',
    );
    mark('state bin days shown');

    final caveat = find.text(
      'Reminders follow the dates your council publishes. A collection can '
      'still be delayed on the day.',
    );
    mark('state reminder caveat shown=${caveat.evaluate().isNotEmpty}');
    expect(caveat, findsOneWidget,
        reason: 'BEHAVIOUR: the reminder card has no published-dates caveat');
    await shot(binding, tester, 'cal-1-reminder-card');

    final calendarTitle = find.text('Add to your calendar');
    await tester.scrollUntilVisible(calendarTitle, 200);
    await tester.pumpAndSettle();

    if (Platform.isAndroid) {
      final explainer = find.text(
        'The Google Calendar app can\u2019t add a calendar feed. Send '
        'yourself the link and add it from a computer.',
      );
      mark('state android explainer shown=${explainer.evaluate().isNotEmpty}');
      expect(explainer, findsOneWidget,
          reason: 'BEHAVIOUR: the Android calendar card lacks the explainer');
      expect(find.text('Paste it into your calendar app.'), findsNothing,
          reason: 'BEHAVIOUR: the old dead-end instruction is still shown');
      await tester.scrollUntilVisible(find.text('Copy link'), 100);
      await tester.pumpAndSettle();
      await shot(binding, tester, 'cal-2-android-card');

      await tester.tap(find.text('Send yourself the link'));
      mark('action tapped Send yourself the link');
      // The share sheet is native: the host captures it and presses Back.
      await Future<void>.delayed(_shareSheetWait);
      await tester.pumpAndSettle();
      final snack = find.textContaining('Sharing isn\u2019t available');
      mark('state share failure snackbar shown=${snack.evaluate().isNotEmpty}');
      expect(snack, findsNothing,
          reason: 'BEHAVIOUR: the share sheet did not open');

      await tester.tap(find.text('Copy link'));
      await tester.pump();
      final copied = await Clipboard.getData(Clipboard.kTextPlain);
      mark('action tapped Copy link; clipboard="${copied?.text}"');
      expect(copied?.text, _calendarUrl,
          reason: 'BEHAVIOUR: Copy link did not copy the feed URL');
    } else {
      final open = find.text('Open calendar feed');
      mark('state ios webcal button shown=${open.evaluate().isNotEmpty}; '
          'send button shown='
          '${find.text('Send yourself the link').evaluate().isNotEmpty}');
      expect(open, findsOneWidget,
          reason: 'BEHAVIOUR: iOS lost its subscribe button');
      expect(find.text('Send yourself the link'), findsNothing,
          reason: 'BEHAVIOUR: iOS shows the Android share flow');
      await shot(binding, tester, 'cal-2-ios-card');
    }

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('About'));
    final stamp = find.textContaining('Build ');
    final stampText =
        stamp.evaluate().isEmpty ? 'none' : tester.widget<Text>(stamp).data;
    mark('state settings build stamp "$stampText" (drive built $_gitSha)');

    await tester.tap(find.text('About'));
    await pumpUntil(tester, find.text('Tom Loosemore\u2019s post'));
    await tester.pumpAndSettle();
    final credit = find.textContaining(
      'Public Digital built WhenIsBins to learn how to respond to AI agents.',
    );
    final oldLine = find.textContaining('isn\u2019t the point');
    mark('state about credit shown=${credit.evaluate().isNotEmpty}; '
        'old line shown=${oldLine.evaluate().isNotEmpty}');
    expect(credit, findsOneWidget,
        reason: 'BEHAVIOUR: About does not credit Public Digital');
    expect(oldLine, findsNothing,
        reason: 'BEHAVIOUR: About still quotes the service unattributed');
    await shot(binding, tester, 'cal-3-about');
  });
}

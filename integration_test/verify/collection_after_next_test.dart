import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/main.dart' as app;
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';

import 'support.dart';

/// verify-when-is-bin feature `set-after-next`.
///
/// Needs no API: an onboarded user with an alternate-week schedule (black bin,
/// recycling, black bin) is ARRANGED through the app's own SettingsProvider
/// before the app starts, as in reminders_switch_after_permission_test.dart.
/// Checks that "Your bin days" shows the next collection and, under it, the
/// one after that with its own bin. Runs on iOS and Android.
const _gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('set-after-next: the bin days show the collection after the '
      'next one', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final fixture = SettingsProvider(prefs);
    final iso = DateFormat('yyyy-MM-dd');
    final label = DateFormat('EEEE d MMMM yyyy');
    final days = [
      (iso.format(DateTime.now().add(const Duration(days: 3))), 'Black bin'),
      (iso.format(DateTime.now().add(const Duration(days: 10))), 'Recycling'),
      (iso.format(DateTime.now().add(const Duration(days: 17))), 'Black bin'),
    ];
    final schedule = Schedule(
      propertyId: 'p:verify-fixture',
      addressMatch: 'exact',
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
      address: 'Verify fixture (not a real address)',
      postcode: 'ZZ99 9ZZ',
      propertyId: schedule.propertyId,
    );
    await fixture.saveSchedule(schedule);
    await fixture.setRemindersEnabled(false);
    await fixture.markOnboarded();
    mark('arrange fixture schedule ${days.map((d) => '${d.$1} ${d.$2}').join(', ')}; '
        'onboarded; platform=${Platform.operatingSystem}');

    // Android screenshots need the Flutter surface rendered to an image.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    app.main();
    await pumpUntil(
      tester,
      find.text('Next collection'),
      reason: 'PRECONDITION: the app did not open on the bin days. Uninstall '
          'it and drive again.',
    );
    await tester.pumpAndSettle();

    final next = label.format(DateTime.parse(days[0].$1));
    final after = label.format(DateTime.parse(days[1].$1));
    final third = label.format(DateTime.parse(days[2].$1));
    mark('state next "$next" shown=${find.text(next).evaluate().isNotEmpty}; '
        'put out black bin shown='
        '${find.text('Put out: Black bin').evaluate().isNotEmpty}');
    mark('state after-that label shown='
        '${find.text('After that').evaluate().isNotEmpty}; '
        '"$after" shown=${find.text(after).evaluate().isNotEmpty}; '
        'recycling shown=${find.text('Recycling').evaluate().isNotEmpty}; '
        'third date "$third" shown=${find.text(third).evaluate().isNotEmpty}');
    expect(find.text(next), findsOneWidget,
        reason: 'BEHAVIOUR: the next collection is missing');
    expect(find.text('After that'), findsOneWidget,
        reason: 'BEHAVIOUR: no collection after the next one');
    expect(find.text(after), findsOneWidget,
        reason: 'BEHAVIOUR: the following date is wrong or missing');
    expect(find.text('Recycling'), findsOneWidget,
        reason: 'BEHAVIOUR: the following bin is wrong or missing');
    expect(find.text(third), findsNothing,
        reason: 'BEHAVIOUR: shows more than the collection after next');
    await shot(binding, tester, 'after-next-1-bin-days');

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.textContaining('Build '));
    mark('state settings build stamp '
        '"${tester.widget<Text>(find.textContaining('Build ')).data}" '
        '(drive built $_gitSha)');
  });
}

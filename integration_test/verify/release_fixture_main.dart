import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/main.dart' as app;
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';

/// An entry point for checking RELEASE builds by hand, where `flutter drive`
/// cannot run. Verification scaffolding only: the app never imports it and it
/// must never be the target of a build that ships.
///
///     flutter build apk --release \
///       --target=integration_test/verify/release_fixture_main.dart
///
/// On a fresh install it saves an onboarded user with two upcoming collections
/// for a made-up property (no API call, no real address) through the app's own
/// SettingsProvider, then starts the real app. Later launches leave the saved
/// state alone, so choices made on the device survive a relaunch.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('onboarded') != true) {
    final fixture = SettingsProvider(prefs);
    final fmt = DateFormat('yyyy-MM-dd');
    final dates = [
      fmt.format(DateTime.now().add(const Duration(days: 7))),
      fmt.format(DateTime.now().add(const Duration(days: 14))),
    ];
    final schedule = Schedule(
      propertyId: 'p:verify-fixture',
      addressMatch: 'exact',
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
  }
  app.main();
}

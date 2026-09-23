import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:when_is_bin_app/providers/settings_provider.dart';
import 'package:when_is_bin_app/services/reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider', () {
    test('defaults to evening reminder and no saved address', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider(await SharedPreferences.getInstance());

      expect(provider.reminderTime, ReminderTime.evening);
      expect(provider.savedAddress, isNull);
      expect(provider.savedPostcode, isNull);
    });

    test('persists a chosen reminder time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.setReminderTime(ReminderTime.morning);

      expect(provider.reminderTime, ReminderTime.morning);
      // A fresh provider reads the persisted value.
      final reloaded = SettingsProvider(prefs);
      expect(reloaded.reminderTime, ReminderTime.morning);
    });

    test('persists a saved address and postcode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);

      await provider.saveAddress(
        address: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
        postcode: 'CB4 2HX',
        propertyId: 'p:4c5ee6c2f2c7c959',
      );

      expect(provider.savedAddress, '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX');
      expect(provider.savedPostcode, 'CB4 2HX');
      expect(provider.savedPropertyId, 'p:4c5ee6c2f2c7c959');

      final reloaded = SettingsProvider(prefs);
      expect(reloaded.savedAddress, '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX');
      expect(reloaded.savedPostcode, 'CB4 2HX');
      expect(reloaded.savedPropertyId, 'p:4c5ee6c2f2c7c959');
    });

    test('clears the saved address', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SettingsProvider(prefs);
      await provider.saveAddress(
        address: '1 Test Road',
        postcode: 'CB4 2HX',
        propertyId: 'p:abc',
      );

      await provider.clearSavedAddress();

      expect(provider.savedAddress, isNull);
      expect(provider.savedPostcode, isNull);
      expect(provider.savedPropertyId, isNull);
    });
  });
}

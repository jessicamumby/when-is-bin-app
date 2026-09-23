import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_scheduler.dart';

/// Persists user preferences: reminder time and the saved address.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs) {
    _reminderTime = _readReminderTime();
    _savedAddress = _prefs.getString(_kAddress);
    _savedPostcode = _prefs.getString(_kPostcode);
    _savedPropertyId = _prefs.getString(_kPropertyId);
  }

  static const _kReminderTime = 'reminder_time';
  static const _kAddress = 'saved_address';
  static const _kPostcode = 'saved_postcode';
  static const _kPropertyId = 'saved_property_id';

  final SharedPreferences _prefs;

  late ReminderTime _reminderTime;
  String? _savedAddress;
  String? _savedPostcode;
  String? _savedPropertyId;

  ReminderTime get reminderTime => _reminderTime;
  String? get savedAddress => _savedAddress;
  String? get savedPostcode => _savedPostcode;
  String? get savedPropertyId => _savedPropertyId;

  ReminderTime _readReminderTime() {
    final stored = _prefs.getString(_kReminderTime);
    return stored == 'morning' ? ReminderTime.morning : ReminderTime.evening;
  }

  Future<void> setReminderTime(ReminderTime time) async {
    _reminderTime = time;
    await _prefs.setString(_kReminderTime, time.name);
    notifyListeners();
  }

  Future<void> saveAddress({
    required String address,
    required String postcode,
    required String propertyId,
  }) async {
    _savedAddress = address;
    _savedPostcode = postcode;
    _savedPropertyId = propertyId;
    await _prefs.setString(_kAddress, address);
    await _prefs.setString(_kPostcode, postcode);
    await _prefs.setString(_kPropertyId, propertyId);
    notifyListeners();
  }

  Future<void> clearSavedAddress() async {
    _savedAddress = null;
    _savedPostcode = null;
    _savedPropertyId = null;
    await _prefs.remove(_kAddress);
    await _prefs.remove(_kPostcode);
    await _prefs.remove(_kPropertyId);
    notifyListeners();
  }
}

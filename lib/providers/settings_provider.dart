import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule.dart';
import '../services/reminder_scheduler.dart';

/// Persists user preferences: reminder time, the saved address and the
/// schedule that belongs to it.
///
/// The schedule is stored so the saved-address shortcut still shows real bin
/// days on a cold start, without another lookup round-trip.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs) {
    _reminderTime = _readReminderTime();
    _savedAddress = _prefs.getString(_kAddress);
    _savedPostcode = _prefs.getString(_kPostcode);
    _savedPropertyId = _prefs.getString(_kPropertyId);
    _readSavedSchedule();
  }

  static const _kReminderTime = 'reminder_time';
  static const _kAddress = 'saved_address';
  static const _kPostcode = 'saved_postcode';
  static const _kPropertyId = 'saved_property_id';
  static const _kSchedule = 'saved_schedule';

  final SharedPreferences _prefs;

  late ReminderTime _reminderTime;
  String? _savedAddress;
  String? _savedPostcode;
  String? _savedPropertyId;

  bool _hasSavedSchedule = false;
  String? _savedAddressMatch;
  List<Collection> _savedCollections = const [];
  List<ByDateEntry> _savedByDate = const [];
  String? _savedCalendarUrl;
  String? _savedRetrievedAt;

  ReminderTime get reminderTime => _reminderTime;
  String? get savedAddress => _savedAddress;
  String? get savedPostcode => _savedPostcode;
  String? get savedPropertyId => _savedPropertyId;

  /// Whether a schedule was persisted alongside the saved address.
  bool get hasSavedSchedule => _hasSavedSchedule;
  String? get savedAddressMatch => _savedAddressMatch;
  List<Collection> get savedCollections => _savedCollections;
  List<ByDateEntry> get savedByDate => _savedByDate;
  String? get savedCalendarUrl => _savedCalendarUrl;
  String? get savedRetrievedAt => _savedRetrievedAt;

  /// The persisted schedule rebuilt as a model, or null when nothing is saved.
  Schedule? get savedSchedule {
    if (!_hasSavedSchedule) return null;
    return Schedule(
      propertyId: _savedPropertyId ?? '',
      addressMatch: _savedAddressMatch ?? '',
      collections: _savedCollections,
      byDate: _savedByDate,
      calendarUrl: _savedCalendarUrl,
      retrievedAt: _savedRetrievedAt,
    );
  }

  ReminderTime _readReminderTime() {
    final stored = _prefs.getString(_kReminderTime);
    return stored == 'morning' ? ReminderTime.morning : ReminderTime.evening;
  }

  void _readSavedSchedule() {
    final stored = _prefs.getString(_kSchedule);
    if (stored == null) return;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      _savedAddressMatch = json['address_match'] as String?;
      _savedCollections = (json['collections'] as List<dynamic>? ?? const [])
          .map((e) => Collection.fromJson(e as Map<String, dynamic>))
          .toList();
      _savedByDate = (json['by_date'] as List<dynamic>? ?? const [])
          .map((e) => ByDateEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _savedCalendarUrl = json['calendar_url'] as String?;
      _savedRetrievedAt = json['retrieved_at'] as String?;
      _hasSavedSchedule = true;
    } on FormatException {
      // Unreadable blob: treat as "nothing saved" rather than crashing every
      // cold start.
    } on TypeError {
      // Blob written in an incompatible shape by an older build — same
      // treatment as unreadable JSON.
    }
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

  /// Persist the looked-up schedule (and the property id it belongs to) so
  /// ScheduleScreen can render it offline on a later cold start.
  Future<void> saveSchedule(Schedule schedule) async {
    _hasSavedSchedule = true;
    // The schedule's own property id is authoritative.
    _savedPropertyId = schedule.propertyId;
    _savedAddressMatch = schedule.addressMatch;
    _savedCollections = schedule.collections;
    _savedByDate = schedule.byDate;
    _savedCalendarUrl = schedule.calendarUrl;
    _savedRetrievedAt = schedule.retrievedAt;

    await _prefs.setString(_kPropertyId, schedule.propertyId);
    await _prefs.setString(
      _kSchedule,
      jsonEncode({
        'property_id': schedule.propertyId,
        'address_match': schedule.addressMatch,
        'collections': schedule.collections.map((c) => c.toJson()).toList(),
        'by_date': schedule.byDate.map((e) => e.toJson()).toList(),
        'calendar_url': schedule.calendarUrl,
        'retrieved_at': schedule.retrievedAt,
      }),
    );
    notifyListeners();
  }

  Future<void> clearSavedAddress() async {
    _savedAddress = null;
    _savedPostcode = null;
    _savedPropertyId = null;
    _hasSavedSchedule = false;
    _savedAddressMatch = null;
    _savedCollections = const [];
    _savedByDate = const [];
    _savedCalendarUrl = null;
    _savedRetrievedAt = null;
    await _prefs.remove(_kAddress);
    await _prefs.remove(_kPostcode);
    await _prefs.remove(_kPropertyId);
    // A schedule without its address would show bin days for an address the
    // user has just removed.
    await _prefs.remove(_kSchedule);
    notifyListeners();
  }
}

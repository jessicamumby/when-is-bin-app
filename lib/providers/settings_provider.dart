import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule.dart';
import '../services/reminder_scheduler.dart';

/// Persists user preferences: reminder time, the saved address and the
/// schedule that belongs to it.
///
/// The schedule is stored so the saved-address shortcut still shows real bin
/// days on a cold start, without another lookup round-trip. Its ETag is stored
/// with it so that shortcut can be re-checked conditionally later, and so is
/// the time it was last checked, so re-checks can be rationed.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _readAll();
  }

  static const _kReminderTime = 'reminder_time';
  static const _kRemindersEnabled = 'reminders_enabled';
  static const _kOnboarded = 'onboarded';
  static const _kAddress = 'saved_address';
  static const _kPostcode = 'saved_postcode';
  static const _kPropertyId = 'saved_property_id';
  static const _kSchedule = 'saved_schedule';
  static const _kScheduleEtag = 'saved_schedule_etag';
  static const _kScheduleCheckedAt = 'schedule_checked_at';

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  late ReminderTime _reminderTime;
  bool _remindersEnabled = false;
  String? _savedAddress;
  String? _savedPostcode;
  String? _savedPropertyId;
  String? _savedScheduleEtag;
  DateTime? _scheduleCheckedAt;
  late bool _onboarded;

  bool _hasSavedSchedule = false;
  bool _savedProvisional = false;
  String? _savedAddressMatch;
  List<Collection> _savedCollections = const [];
  List<ByDateEntry> _savedByDate = const [];
  String? _savedCalendarUrl;
  String? _savedRetrievedAt;
  String? _savedNotes;

  ReminderTime get reminderTime => _reminderTime;

  /// Whether the user has reminders switched on. Persisted so the switch still
  /// reads "on" after a cold start, matching the notifications that are
  /// actually scheduled.
  bool get remindersEnabled => _remindersEnabled;

  String? get savedAddress => _savedAddress;
  String? get savedPostcode => _savedPostcode;
  String? get savedPropertyId => _savedPropertyId;

  /// Whether the first-launch onboarding has been completed.
  bool get isOnboarded => _onboarded;

  /// The ETag that came with the saved schedule, to be sent as `If-None-Match`
  /// when the schedule is re-checked. Null until the API has told us one.
  String? get savedScheduleEtag => _savedScheduleEtag;

  /// When the saved schedule was last confirmed against the API: by a lookup,
  /// or by a re-check that found it current or replaced it. Null until then.
  DateTime? get scheduleCheckedAt => _scheduleCheckedAt;

  /// Whether a schedule was persisted alongside the saved address.
  bool get hasSavedSchedule => _hasSavedSchedule;
  String? get savedAddressMatch => _savedAddressMatch;
  List<Collection> get savedCollections => _savedCollections;
  List<ByDateEntry> get savedByDate => _savedByDate;
  String? get savedCalendarUrl => _savedCalendarUrl;
  String? get savedRetrievedAt => _savedRetrievedAt;

  /// The council's own caveats for the saved schedule — the plain-English
  /// reasons its dates may still move.
  String? get savedNotes => _savedNotes;

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
      provisional: _savedProvisional,
      notes: _savedNotes,
    );
  }

  /// Read every persisted value into memory, replacing what was there.
  void _readAll() {
    _reminderTime = _readReminderTime();
    _remindersEnabled = _prefs.getBool(_kRemindersEnabled) ?? false;
    _savedAddress = _prefs.getString(_kAddress);
    _savedPostcode = _prefs.getString(_kPostcode);
    _savedPropertyId = _prefs.getString(_kPropertyId);
    _savedScheduleEtag = _prefs.getString(_kScheduleEtag);
    _scheduleCheckedAt = _readCheckedAt();
    _readSavedSchedule();
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
  }

  /// Re-read everything from storage, and say whether the saved schedule
  /// changed.
  ///
  /// The background re-check runs in its own isolate, with its own
  /// SharedPreferences cache, and writes straight to storage. This isolate's
  /// cache never sees those writes, so without a reload the next reminder
  /// sync here would re-derive the reminders from the schedule the background
  /// task has just replaced, undoing its work.
  Future<bool> reload() async {
    final before = _prefs.getString(_kSchedule);
    await _prefs.reload();
    _readAll();
    notifyListeners();
    return _prefs.getString(_kSchedule) != before;
  }

  DateTime? _readCheckedAt() {
    final stored = _prefs.getString(_kScheduleCheckedAt);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  ReminderTime _readReminderTime() {
    final stored = _prefs.getString(_kReminderTime);
    return stored == 'morning' ? ReminderTime.morning : ReminderTime.evening;
  }

  void _readSavedSchedule() {
    _clearSavedScheduleFields();
    final stored = _prefs.getString(_kSchedule);
    if (stored == null) return;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      _savedAddressMatch = json['address_match'] as String?;
      _savedProvisional = json['provisional'] as bool? ?? false;
      _savedCollections = (json['collections'] as List<dynamic>? ?? const [])
          .map((e) => Collection.fromJson(e as Map<String, dynamic>))
          .toList();
      _savedByDate = (json['by_date'] as List<dynamic>? ?? const [])
          .map((e) => ByDateEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _savedCalendarUrl = json['calendar_url'] as String?;
      _savedRetrievedAt = json['retrieved_at'] as String?;
      _savedNotes = json['notes'] as String?;
      _hasSavedSchedule = true;
    } on FormatException {
      // Unreadable blob: treat as "nothing saved" rather than crashing every
      // cold start.
      _clearSavedScheduleFields();
    } on TypeError {
      // Blob written in an incompatible shape by an older build — same
      // treatment as unreadable JSON.
      _clearSavedScheduleFields();
    }
  }

  void _clearSavedScheduleFields() {
    _hasSavedSchedule = false;
    _savedProvisional = false;
    _savedAddressMatch = null;
    _savedCollections = const [];
    _savedByDate = const [];
    _savedCalendarUrl = null;
    _savedRetrievedAt = null;
    _savedNotes = null;
  }

  Future<void> setReminderTime(ReminderTime time) async {
    _reminderTime = time;
    await _prefs.setString(_kReminderTime, time.name);
    notifyListeners();
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    _remindersEnabled = enabled;
    await _prefs.setBool(_kRemindersEnabled, enabled);
    notifyListeners();
  }

  Future<void> saveAddress({
    required String address,
    required String postcode,
    required String propertyId,
  }) async {
    // An ETag only describes the property it came from, so a different address
    // must not inherit the old one: it would make the next conditional request
    // report "unchanged" for a schedule we have never seen.
    final changedProperty = propertyId != _savedPropertyId;
    _savedAddress = address;
    _savedPostcode = postcode;
    _savedPropertyId = propertyId;
    await _prefs.setString(_kAddress, address);
    await _prefs.setString(_kPostcode, postcode);
    await _prefs.setString(_kPropertyId, propertyId);
    if (changedProperty) await _setScheduleEtag(null);
    notifyListeners();
  }

  /// Persist the looked-up schedule (and the property id it belongs to) so
  /// ScheduleScreen can render it offline on a later cold start.
  ///
  /// Pass the [etag] the server sent with the schedule to make the next check
  /// conditional; leaving it out keeps whatever tag is already stored.
  ///
  /// Every schedule saved here has just come back from the API, so saving it
  /// also stamps [scheduleCheckedAt].
  Future<void> saveSchedule(Schedule schedule, {String? etag}) async {
    final changedProperty = schedule.propertyId != _savedPropertyId;
    _hasSavedSchedule = true;
    _savedProvisional = schedule.provisional;
    // The schedule's own property id is authoritative.
    _savedPropertyId = schedule.propertyId;
    _savedAddressMatch = schedule.addressMatch;
    _savedCollections = schedule.collections;
    _savedByDate = schedule.byDate;
    _savedCalendarUrl = schedule.calendarUrl;
    _savedRetrievedAt = schedule.retrievedAt;
    _savedNotes = schedule.notes;

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
        'provisional': schedule.provisional,
        'notes': schedule.notes,
      }),
    );
    if (etag != null) {
      await _setScheduleEtag(etag);
    } else if (changedProperty) {
      await _setScheduleEtag(null);
    }
    await _setCheckedAt(_now());
    notifyListeners();
  }

  /// Record a re-check that found the saved schedule still current.
  Future<void> markScheduleChecked() async {
    await _setCheckedAt(_now());
    notifyListeners();
  }

  Future<void> _setCheckedAt(DateTime? at) async {
    _scheduleCheckedAt = at?.toUtc();
    if (at == null) {
      await _prefs.remove(_kScheduleCheckedAt);
    } else {
      await _prefs.setString(_kScheduleCheckedAt, at.toUtc().toIso8601String());
    }
  }

  Future<void> _setScheduleEtag(String? etag) async {
    _savedScheduleEtag = etag;
    if (etag == null) {
      await _prefs.remove(_kScheduleEtag);
    } else {
      await _prefs.setString(_kScheduleEtag, etag);
    }
  }

  /// Marks the onboarding flow as complete. Persisted so it only shows
  /// on the first launch.
  Future<void> markOnboarded() async {
    _onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  Future<void> clearSavedAddress() async {
    _savedAddress = null;
    _savedPostcode = null;
    _savedPropertyId = null;
    _clearSavedScheduleFields();
    _savedScheduleEtag = null;
    await _prefs.remove(_kAddress);
    await _prefs.remove(_kPostcode);
    await _prefs.remove(_kPropertyId);
    await _prefs.remove(_kScheduleEtag);
    await _setCheckedAt(null);
    // A schedule without its address would show bin days for an address the
    // user has just removed.
    await _prefs.remove(_kSchedule);
    notifyListeners();
  }
}
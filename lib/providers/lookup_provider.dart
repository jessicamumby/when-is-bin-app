import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/address_lookup.dart';
import '../models/lookup.dart';
import '../models/schedule.dart';
import '../services/when_is_bins_api.dart';

/// Orchestrates the postcode → address → lookup → schedule journey.
class LookupProvider extends ChangeNotifier {
  LookupProvider({required WhenIsBinsApi api}) : _api = api;

  final WhenIsBinsApi _api;

  String? _postcode;
  AddressLookup? _addressLookup;
  Schedule? _schedule;
  bool _isLoading = false;
  ApiException? _error;

  String? get postcode => _postcode;
  AddressLookup? get addressLookup => _addressLookup;
  Schedule? get schedule => _schedule;
  bool get isLoading => _isLoading;
  ApiException? get error => _error;

  /// Resolve a postcode to its council and required address input.
  Future<void> lookupPostcode(String postcode) async {
    _postcode = postcode;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      _addressLookup = await _api.getAddresses(postcode);
    } on ApiException catch (e) {
      _error = e;
      _addressLookup = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit a selected address and poll until the lookup settles.
  Future<void> selectAddress(
    AddressCandidate candidate, {
    required String postcode,
  }) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      final lookup = await _api.createLookup(
        {'postcode': postcode, 'property_id': candidate.id},
        idempotencyKey: _newIdempotencyKey(),
      );
      final settled = await _pollUntilSettled(lookup);
      if (settled.status == 'failed') {
        _error = ApiException(
          statusCode: 0,
          problem: 'lookup_failed',
          detail: settled.detail,
        );
        _schedule = null;
      } else {
        _schedule = settled.result;
      }
    } on ApiException catch (e) {
      _error = e;
      _schedule = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Hydrate the schedule from data persisted by `SettingsProvider`, so the
  /// saved-address shortcut renders real bin days on a cold start without
  /// another lookup. A null [schedule] (nothing saved) is a no-op.
  void restoreSchedule(Schedule? schedule) {
    if (schedule == null) return;
    _error = null;
    _schedule = schedule;
    notifyListeners();
  }

  Future<Lookup> _pollUntilSettled(Lookup initial) async {
    var lookup = initial;
    while (lookup.isPending) {
      await Future<void>.delayed(const Duration(seconds: 1));
      lookup = await _api.getLookup(lookup.id);
    }
    return lookup;
  }

  /// A fresh, space-free idempotency key. The WhenIsBins API requires the
  /// `Idempotency-Key` to be 1-128 *visible* ASCII characters, so it must not
  /// contain whitespace (a postcode like 'CB4 2HX' would otherwise break it).
  String _newIdempotencyKey() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

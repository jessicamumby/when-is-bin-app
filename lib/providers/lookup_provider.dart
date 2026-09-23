import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/address_lookup.dart';
import '../models/lookup.dart';
import '../models/schedule.dart';
import '../services/when_is_bins_api.dart';

/// Orchestrates the postcode → address → lookup → schedule journey.
class LookupProvider extends ChangeNotifier {
  LookupProvider({
    required WhenIsBinsApi api,
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? now,
    this.maxWait = defaultMaxWait,
  })  : _api = api,
        _delay = delay ?? ((Duration duration) => Future<void>.delayed(duration)),
        _now = now ?? DateTime.now;

  /// How long a lookup is waited for before the app stops and keeps the id for
  /// a later check. The API guide's own client waits two minutes at most, and
  /// a slow lookup is never resubmitted.
  static const defaultMaxWait = Duration(minutes: 2);

  /// The pause before reconnecting to `/wait` when the server asked for no
  /// particular wait. The endpoint holds the connection open by itself, so this
  /// only stops a server that answers instantly from being hammered.
  static const defaultReconnectDelay = Duration(seconds: 1);

  final WhenIsBinsApi _api;
  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _now;

  /// The longest a single lookup will be waited for, in total.
  final Duration maxWait;

  String? _postcode;
  AddressLookup? _addressLookup;
  Schedule? _schedule;
  bool _isLoading = false;
  ApiException? _error;
  String? _pendingLookupId;

  String? get postcode => _postcode;
  AddressLookup? get addressLookup => _addressLookup;
  Schedule? get schedule => _schedule;
  bool get isLoading => _isLoading;
  ApiException? get error => _error;

  /// The id of a lookup that was still running when the wait budget ran out.
  /// It is kept so a later check can pick the lookup up (see
  /// [continuePendingLookup]) instead of submitting the same address again.
  String? get pendingLookupId => _pendingLookupId;

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

  /// Submit a selected address and wait until the lookup settles.
  Future<void> selectAddress(
    AddressCandidate candidate, {
    required String postcode,
  }) async {
    _error = null;
    _pendingLookupId = null;
    _isLoading = true;
    notifyListeners();
    try {
      final lookup = await _api.createLookup(
        {'postcode': postcode, 'property_id': candidate.id},
        idempotencyKey: _newIdempotencyKey(),
      );
      _applySettled(await _pollUntilSettled(lookup));
    } on ApiException catch (e) {
      _error = e;
      _schedule = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pick up a lookup that was still running when the wait budget ran out.
  ///
  /// It reconnects to the same lookup (never a new one) and keeps the partial
  /// schedule on screen while it waits, so a slow council is not paid for
  /// twice. A no-op when nothing is pending.
  Future<void> continuePendingLookup() async {
    final id = _pendingLookupId;
    if (id == null) return;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      _applySettled(await _pollUntilSettled(Lookup(id: id, status: 'queued')));
    } on ApiException catch (e) {
      // Keep whatever partial result is on screen: only the wait failed.
      _error = e;
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

  /// Long-poll a lookup until it settles or [maxWait] runs out.
  ///
  /// `/wait` holds the request open until the lookup changes (~25s), so this
  /// reconnects with the cursor the server handed back rather than snapshotting
  /// on a timer — and only ever has one wait open at a time.
  Future<Lookup> _pollUntilSettled(Lookup initial) async {
    var lookup = initial;
    String? cursor;
    final deadline = _now().add(maxWait);
    while (lookup.isPending) {
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) break;
      final wait = await _api.waitForLookup(lookup.id, after: cursor);
      cursor = wait.cursor ?? cursor;
      lookup = wait.lookup;
      if (lookup.isTerminal) break;
      // Respect a Retry-After, but never sleep past the budget: there would be
      // no request left to make on the other side of it.
      final requested = wait.retryAfter ?? defaultReconnectDelay;
      await _delay(requested > remaining ? remaining : requested);
    }
    return lookup;
  }

  /// Record a lookup that settled — or one that is still running when the wait
  /// budget ran out.
  void _applySettled(Lookup settled) {
    if (settled.status == 'failed') {
      _error = ApiException(
        statusCode: 0,
        problem: 'lookup_failed',
        detail: settled.detail,
      );
      _schedule = null;
      _pendingLookupId = null;
      return;
    }
    // A partial result beats nothing, and the id is kept for a later check
    // rather than resubmitting a lookup that is merely slow.
    _schedule = settled.result ?? _schedule;
    _pendingLookupId = settled.isPending ? settled.id : null;
  }

  /// A fresh, space-free idempotency key. The WhenIsBins API requires the
  /// `Idempotency-Key` to be 1-128 *visible* ASCII characters, so it must not
  /// contain whitespace (a postcode like 'CB4 2HX' would otherwise break it).
  String _newIdempotencyKey() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

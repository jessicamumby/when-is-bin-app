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

  /// The `problem` on the 429 the API's rate limiter answers with. It is the
  /// one failure that says "not now", not "no".
  static const _rateLimitedProblem = 'rate_limited';

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
  Lookup? _failedLookup;

  /// The lookup that is in flight right now, if any: what the loading screen
  /// needs to say how long this council usually takes and how far along the
  /// lookup has got.
  Lookup? _activeLookup;

  /// The last address submitted, kept whole so it can be resubmitted with
  /// `allow_postcode_representative` once the user consents.
  Map<String, dynamic>? _lastSubmittedAddress;

  String? get postcode => _postcode;
  AddressLookup? get addressLookup => _addressLookup;
  Schedule? get schedule => _schedule;
  bool get isLoading => _isLoading;
  ApiException? get error => _error;

  /// The id of a lookup that was still running when the wait budget ran out.
  /// It is kept so a later check can pick the lookup up (see
  /// [continuePendingLookup]) instead of submitting the same address again.
  String? get pendingLookupId => _pendingLookupId;

  /// The lookup that failed, whole.
  ///
  /// [error] is all the UI needs to say *that* a lookup failed, but a failed
  /// lookup also carries the reason (`problem`, e.g. `address_not_found`), the
  /// addresses the council offered instead (`candidates`), and the link to
  /// check by hand (`council.lookupUrl`) — that is where the user goes next, so
  /// it is exposed as it arrived rather than flattened into a message.
  Lookup? get failedLookup => _failedLookup;

  /// The lookup that is in flight, or null when nothing is being waited for.
  ///
  /// It carries the council's own figures for the wait — how long it usually
  /// takes, what stage it has reached, and how many lookups are ahead of this
  /// one — so the loading screen can say something honest instead of spinning.
  Lookup? get activeLookup => _activeLookup;

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

  /// Submit any address shape a council asked for and wait until the lookup
  /// settles.
  ///
  /// [address] holds the fields the council's `required_input` called for —
  /// `property`, `street`, `locality`, `normal_weekday`, `property_type` — or
  /// `property_id` for a picked candidate, and is spread into the body beside
  /// the postcode. A fresh idempotency key per submission, and the shared
  /// `/wait` long-poll, mean every journey is submitted exactly like the
  /// candidate journey is.
  Future<void> submitLookup({
    required String postcode,
    required Map<String, dynamic> address,
  }) {
    // Kept so the user can consent to a neighbour's answer later without
    // retyping the address (see [submitWithPostcodeRepresentative]).
    _lastSubmittedAddress = address;
    return _submit({'postcode': postcode, ...address});
  }

  /// Re-submit the last address asking the council to answer for the nearest
  /// property to the postcode instead of the exact one.
  ///
  /// Only worth offering after a `postcode_representative: 'opt_in'` answer
  /// from `/addresses` and a lookup that failed with `address_not_found`: it is
  /// the user's consent that decides, so this is a deliberate call and never
  /// automatic. A no-op before any submission. The body repeats the original
  /// address fields (so the council sees the same address), adds
  /// `allow_postcode_representative: true`, and carries its own idempotency
  /// key — this is new work, not a retry of the first one.
  Future<void> submitWithPostcodeRepresentative({
    required String postcode,
  }) {
    final address = _lastSubmittedAddress;
    if (address == null) return Future<void>.value();
    return _submit({
      'postcode': postcode,
      ...address,
      'allow_postcode_representative': true,
    });
  }

  /// Create a lookup for [body] and wait for it to settle — the journey every
  /// submission shares.
  Future<void> _submit(Map<String, dynamic> body) async {
    _error = null;
    _pendingLookupId = null;
    _activeLookup = null;
    _isLoading = true;
    notifyListeners();
    String? submittedId;
    try {
      final lookup = await _api.createLookup(
        body,
        idempotencyKey: _newIdempotencyKey(),
      );
      submittedId = lookup.id;
      // The created lookup is what the user is now waiting for: its council's
      // expected wait and progress are theirs to see.
      _activeLookup = lookup;
      notifyListeners();
      _applySettled(await _pollUntilSettled(lookup));
    } on ApiException catch (e) {
      // The lookup itself exists on the server even when the wait failed
      // (a dropped connection, a timeout), so its id is kept: a later check
      // picks the lookup up instead of paying for the same work twice.
      _pendingLookupId = submittedId;
      _error = e;
      _schedule = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit a selected address and wait until the lookup settles.
  Future<void> selectAddress(
    AddressCandidate candidate, {
    required String postcode,
  }) {
    return submitLookup(
      postcode: postcode,
      address: {'property_id': candidate.id},
    );
  }

  /// Re-ask `/addresses` with a narrower `q` — the follow-up to a council that
  /// answered `input_options.needs_more_query`.
  ///
  /// A failed re-query keeps the options already on screen: losing the list the
  /// user was picking from would strand them mid-form, and the error tells them
  /// to try again.
  Future<void> refineAddressLookup(String q) async {
    final postcode = _postcode;
    if (postcode == null) return;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      _addressLookup = await _api.getAddresses(postcode, q: q);
    } on ApiException catch (e) {
      _error = e;
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
      final LookupWait wait;
      try {
        wait = await _api.waitForLookup(lookup.id, after: cursor);
      } on ApiException catch (e) {
        // On a mobile network many phones share one IPv4 address, so the
        // user's fifth open wait can be rate limited through no fault of
        // their own. The lookup itself is still running: wait out the
        // Retry-After the server asked for and reconnect to the SAME lookup
        // with the SAME cursor. Any other failure is the caller's to report.
        final retryAfter = e.retryAfter;
        if (e.problem != _rateLimitedProblem || retryAfter == null) rethrow;
        await _sleepWithin(retryAfter, remaining);
        continue;
      }
      cursor = wait.cursor ?? cursor;
      lookup = wait.lookup;
      // Every answer from /wait re-states the council's own figures, so the
      // loading screen can update its wait and progress as the lookup moves.
      _activeLookup = lookup;
      notifyListeners();
      if (lookup.isTerminal) break;
      // Respect a Retry-After, but never sleep past the budget: there would be
      // no request left to make on the other side of it.
      await _sleepWithin(wait.retryAfter ?? defaultReconnectDelay, remaining);
    }
    return lookup;
  }

  /// Sleep for [requested], but never past what is left of the wait budget:
  /// there would be no request left to make on the other side of it.
  Future<void> _sleepWithin(Duration requested, Duration remaining) {
    return _delay(requested > remaining ? remaining : requested);
  }

  /// Record a lookup that settled — or one that is still running when the wait
  /// budget ran out.
  void _applySettled(Lookup settled) {
    // A terminal lookup is nothing to wait for; one that is still running is
    // kept, because it is still in flight behind a later check.
    _activeLookup = settled.isTerminal ? null : settled;
    if (settled.status == 'failed') {
      // The whole lookup is kept: the UI needs its real `problem`, the
      // candidate addresses and the council's own link, none of which survive
      // in an ApiException.
      _failedLookup = settled;
      _error = ApiException(
        statusCode: 0,
        problem: 'lookup_failed',
        detail: settled.detail,
      );
      _schedule = null;
      _pendingLookupId = null;
      return;
    }
    _failedLookup = null;
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

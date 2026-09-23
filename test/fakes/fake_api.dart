import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

/// A controllable fake of [WhenIsBinsApi] for provider tests.
class FakeWhenIsBinsApi implements WhenIsBinsApi {
  AddressLookup? addressLookup;
  ApiException? error;

  /// The answer to `createLookup` (its first entry, or a done lookup).
  List<Lookup> lookupResponses = [];
  int lookupCallCount = 0;
  int createLookupCalls = 0;

  /// The answers to `waitForLookup`, in order. The last one repeats once the
  /// list is exhausted, so an "always still running" server is one entry.
  List<Lookup> waitResponses = [];

  /// The `X-Lookup-Cursor` handed back on each wait call, and the `after`
  /// value each call was made with.
  List<String?> cursors = [];
  List<String?> afterCalls = [];

  /// The `Retry-After`, when the server sends one, per wait call.
  List<Duration?> retryAfters = [];
  int waitCallCount = 0;

  Schedule? schedule;
  String? lastPostcode;
  String? lastIdempotencyKey;

  /// The answer to `checkSchedule`, and the conditional header it was asked
  /// for.
  ScheduleCheck? scheduleCheck;
  ApiException? scheduleCheckError;
  int scheduleCheckCalls = 0;
  String? lastScheduleToken;
  String? lastScheduleEtag;

  @override
  String get baseUrl => 'https://fake';

  @override
  String? get token => null;

  @override
  Duration get timeout => WhenIsBinsApi.defaultTimeout;

  @override
  Future<AddressLookup> getAddresses(String postcode, {String? q}) async {
    lastPostcode = postcode;
    if (error != null) throw error!;
    return addressLookup ??
        AddressLookup(postcode: postcode, requiredInput: 'none');
  }

  @override
  Future<Lookup> createLookup(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async {
    createLookupCalls++;
    lastIdempotencyKey = idempotencyKey;
    if (error != null) throw error!;
    if (lookupResponses.isEmpty) {
      return Lookup(id: 'lookup-1', status: 'done');
    }
    return lookupResponses.first;
  }

  @override
  Future<Lookup> getLookup(String lookupId) async {
    lookupCallCount++;
    if (lookupResponses.length > 1) {
      return lookupResponses[lookupCallCount.clamp(1, lookupResponses.length - 1)];
    }
    return lookupResponses.isEmpty
        ? Lookup(id: lookupId, status: 'done')
        : lookupResponses.last;
  }

  @override
  Future<LookupWait> waitForLookup(String lookupId, {String? after}) async {
    afterCalls.add(after);
    final index = waitCallCount++;
    if (error != null) throw error!;
    return LookupWait(
      lookup: _waitAnswer(index, lookupId),
      cursor: index < cursors.length ? cursors[index] : null,
      retryAfter: index < retryAfters.length ? retryAfters[index] : null,
    );
  }

  Lookup _waitAnswer(int index, String lookupId) {
    if (waitResponses.isEmpty) return Lookup(id: lookupId, status: 'done');
    return index < waitResponses.length
        ? waitResponses[index]
        : waitResponses.last;
  }

  @override
  Future<ScheduleCheck> checkSchedule(
    String propertyToken, {
    String? etag,
  }) async {
    scheduleCheckCalls++;
    lastScheduleToken = propertyToken;
    lastScheduleEtag = etag;
    if (scheduleCheckError != null) throw scheduleCheckError!;
    return scheduleCheck ?? const ScheduleCheck.unchanged();
  }
}

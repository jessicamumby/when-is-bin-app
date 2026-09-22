import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

/// A controllable fake of [WhenIsBinsApi] for provider tests.
class FakeWhenIsBinsApi implements WhenIsBinsApi {
  AddressLookup? addressLookup;
  ApiException? error;
  List<Lookup> lookupResponses = [];
  int lookupCallCount = 0;
  Schedule? schedule;
  String? lastPostcode;
  String? lastIdempotencyKey;

  @override
  String get baseUrl => 'https://fake';

  @override
  String? get token => null;

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
    lastIdempotencyKey = idempotencyKey;
    if (lookupResponses.isEmpty) {
      return Lookup(id: 'lookup-1', status: 'done');
    }
    return lookupResponses[0];
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
  Future<Schedule> getSchedule(String propertyToken, {String? etag}) async {
    return schedule ??
        Schedule(propertyId: 'p:$propertyToken', addressMatch: 'exact');
  }
}

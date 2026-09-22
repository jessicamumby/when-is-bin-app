import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../fakes/fake_api.dart';

void main() {
  group('LookupProvider', () {
    test('starts empty', () {
      final provider = LookupProvider(api: FakeWhenIsBinsApi());

      expect(provider.postcode, isNull);
      expect(provider.addressLookup, isNull);
      expect(provider.schedule, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('lookupPostcode resolves the address and clears error', () async {
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: 'CB4 2HX',
          requiredInput: 'property_id',
          candidates: const [
            AddressCandidate(
              id: 'p:4c5ee6c2f2c7c959',
              label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
            ),
          ],
        );
      final provider = LookupProvider(api: api);

      await provider.lookupPostcode('CB4 2HX');

      expect(provider.postcode, 'CB4 2HX');
      expect(provider.addressLookup?.candidates, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('lookupPostcode surfaces an ApiException as error', () async {
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 404,
          problem: 'postcode_outside_coverage',
          detail: 'Postcode is outside coverage.',
        );
      final provider = LookupProvider(api: api);

      await provider.lookupPostcode('ZZ99 9ZZ');

      expect(provider.error?.problem, 'postcode_outside_coverage');
      expect(provider.addressLookup, isNull);
    });

    test('selectAddress creates a lookup and polls until done', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'queued',
            expectedWaitSeconds: 1,
          ),
          Lookup(
            id: 'lookup-1',
            status: 'done',
            result: Schedule(
              propertyId: 'p:4c5ee6c2f2c7c959',
              addressMatch: 'exact',
              collections: const [
                Collection(
                  name: 'Black bin',
                  wasteType: 'refuse',
                  dates: ['2026-09-10'],
                ),
              ],
            ),
          ),
        ];
      final provider = LookupProvider(api: api);

      await provider.selectAddress(
        const AddressCandidate(
          id: 'p:4c5ee6c2f2c7c959',
          label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
        ),
        postcode: 'CB4 2HX',
      );

      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.schedule?.collections, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('selectAddress surfaces a failed lookup detail', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'failed',
            detail: "The council's system doesn't list that exact address.",
          ),
        ];
      final provider = LookupProvider(api: api);

      await provider.selectAddress(
        const AddressCandidate(id: 'p:abc', label: '1 Test Road'),
        postcode: 'CB4 2HX',
      );

      expect(provider.schedule, isNull);
      expect(provider.error?.detail,
          "The council's system doesn't list that exact address.");
    });
  });
}

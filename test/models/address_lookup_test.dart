import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';

void main() {
  group('AddressLookup.fromJson', () {
    test('parses a council with a property candidate list', () {
      final json = {
        'postcode': 'CB4 2HX',
        'council': {
          'id': 'E07000008',
          'name': 'Cambridge City Council',
          'lookup_url':
              'https://www.cambridge.gov.uk/check-when-your-bin-will-be-emptied',
          'expected_wait_seconds': 8,
          'success_rate': 0.96,
        },
        'required_input': 'property_id',
        'postcode_representative': 'opt_in',
        'candidates_source': 'council',
        'candidates': [
          {
            'id': 'p:4c5ee6c2f2c7c959',
            'label': '15 EXAMPLE COURT, EXAMPLE ROAD, CAMBRIDGE, CB4 2HX',
          },
        ],
      };

      final lookup = AddressLookup.fromJson(json);

      expect(lookup.postcode, 'CB4 2HX');
      expect(lookup.council?.id, 'E07000008');
      expect(lookup.council?.name, 'Cambridge City Council');
      expect(lookup.requiredInput, 'property_id');
      expect(lookup.postcodeRepresentative, 'opt_in');
      expect(lookup.candidatesSource, 'council');
      expect(lookup.candidates, hasLength(1));
      expect(lookup.candidates!.first.id, 'p:4c5ee6c2f2c7c959');
      expect(lookup.candidates!.first.label,
          '15 EXAMPLE COURT, EXAMPLE ROAD, CAMBRIDGE, CB4 2HX');
    });

    test('handles a council that needs free-text property input', () {
      final json = {
        'postcode': 'EH14 7AL',
        'council': {
          'id': 'S12000036',
          'name': 'City of Edinburgh Council',
        },
        'required_input': 'property',
        'candidates_source': 'unavailable',
        'candidates': [],
      };

      final lookup = AddressLookup.fromJson(json);

      expect(lookup.requiredInput, 'property');
      expect(lookup.candidatesSource, 'unavailable');
      expect(lookup.candidates, isEmpty);
      expect(lookup.council?.expectedWaitSeconds, isNull);
      expect(lookup.council?.successRate, isNull);
    });

    test('parses input_options for road/area pickers', () {
      final json = {
        'postcode': 'EH14 7AL',
        'required_input': 'street',
        'input_options': {
          'field': 'street',
          'shape': 'short_list',
          'needs_more_query': true,
          'not_listed_value': '__not_listed__',
          'options': [
            {
              'value': 'A70--Glenbrook Rd To B7031',
              'label': 'A70--Glenbrook Rd To B7031',
            },
          ],
        },
      };

      final lookup = AddressLookup.fromJson(json);

      expect(lookup.inputOptions?.field, 'street');
      expect(lookup.inputOptions?.needsMoreQuery, isTrue);
      expect(lookup.inputOptions?.notListedValue, '__not_listed__');
      expect(lookup.inputOptions?.options, hasLength(1));
      expect(lookup.inputOptions?.options!.first.value,
          'A70--Glenbrook Rd To B7031');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/address_input.dart';

void main() {
  group('AddressInputSpec.forRequiredInput', () {
    test('maps every required_input the API documents to its fields', () {
      expect(AddressInputSpec.forRequiredInput('none').fields, isEmpty);
      expect(AddressInputSpec.forRequiredInput('property_id').fields, isEmpty);
      expect(AddressInputSpec.forRequiredInput('property').fields, [
        AddressField.property,
      ]);
      expect(AddressInputSpec.forRequiredInput('street').fields, [
        AddressField.street,
      ]);
      expect(AddressInputSpec.forRequiredInput('road_and_locality').fields, [
        AddressField.street,
        AddressField.locality,
      ]);
      expect(AddressInputSpec.forRequiredInput('street_and_property').fields, [
        AddressField.street,
        AddressField.property,
      ]);
      expect(AddressInputSpec.forRequiredInput('settlement').fields, [
        AddressField.locality,
      ]);
      expect(AddressInputSpec.forRequiredInput('settlement_or_road').fields, [
        AddressField.locality,
      ]);
      expect(AddressInputSpec.forRequiredInput('normal_weekday').fields, [
        AddressField.weekday,
      ]);
      expect(
        AddressInputSpec.forRequiredInput('normal_weekday_and_locality').fields,
        [AddressField.weekday, AddressField.locality],
      );
      expect(AddressInputSpec.forRequiredInput('property_type').fields, [
        AddressField.propertyType,
      ]);
    });

    test('asks for nothing extra when the required_input is unknown', () {
      expect(AddressInputSpec.forRequiredInput('something_new').fields, isEmpty);
      expect(AddressInputSpec.forRequiredInput('something_new').isEmpty, isTrue);
    });

    test('includes() reports the fields the council asked for', () {
      final spec = AddressInputSpec.forRequiredInput('street_and_property');

      expect(spec.includes(AddressField.street), isTrue);
      expect(spec.includes(AddressField.property), isTrue);
      expect(spec.includes(AddressField.locality), isFalse);
      expect(spec.includes(AddressField.weekday), isFalse);
      expect(spec.isEmpty, isFalse);
    });
  });

  group('buildAddressBody', () {
    test('sends each required_input as the API documents it', () {
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('property'),
          property: '15 Example Court',
        ),
        {'property': '15 Example Court'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('street'),
          street: 'Example Road',
        ),
        {'street': 'Example Road'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('road_and_locality'),
          street: 'Example Road',
          locality: 'Cambridge',
        ),
        {'street': 'Example Road', 'locality': 'Cambridge'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('street_and_property'),
          street: 'Example Road',
          property: '15',
        ),
        {'street': 'Example Road', 'property': '15'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('settlement'),
          locality: 'Currie',
        ),
        {'locality': 'Currie'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('settlement_or_road'),
          locality: 'A70--Glenbrook Rd To B7031',
        ),
        {'locality': 'A70--Glenbrook Rd To B7031'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('normal_weekday'),
          weekday: 'Monday',
        ),
        {'normal_weekday': 'Monday'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('normal_weekday_and_locality'),
          weekday: 'Monday',
          locality: 'Currie',
        ),
        {'normal_weekday': 'Monday', 'locality': 'Currie'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('property_type'),
          propertyType: 'housing_estate',
        ),
        {'property_type': 'housing_estate'},
      );
    });

    test('names the weekday field normal_weekday, not weekday', () {
      final body = buildAddressBody(
        spec: AddressInputSpec.forRequiredInput('normal_weekday'),
        weekday: 'Tuesday',
      );

      expect(body.keys, ['normal_weekday']);
    });

    test('never sends a field the required_input did not ask for', () {
      final body = buildAddressBody(
        spec: AddressInputSpec.forRequiredInput('street'),
        property: '15 Example Court',
        street: 'Example Road',
        locality: 'Cambridge',
        weekday: 'Monday',
        propertyType: 'housing_estate',
      );

      expect(body, {'street': 'Example Road'});
    });

    test('an empty spec sends nothing at all', () {
      final body = buildAddressBody(
        spec: AddressInputSpec.forRequiredInput('none'),
        property: '15 Example Court',
        street: 'Example Road',
        weekday: 'Monday',
      );

      expect(body, isEmpty);
    });

    test('trims values and omits blanks so a blank is a missing answer', () {
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('street'),
          street: '  Example Road  ',
        ),
        {'street': 'Example Road'},
      );
      expect(
        buildAddressBody(
          spec: AddressInputSpec.forRequiredInput('road_and_locality'),
          street: '   ',
          locality: 'Cambridge',
        ),
        {'locality': 'Cambridge'},
      );
      expect(
        buildAddressBody(spec: AddressInputSpec.forRequiredInput('property')),
        isEmpty,
      );
    });
  });

  group('resolvedChoice', () {
    test('sends the picked option value', () {
      expect(
        resolvedChoice(selected: 'A70--Glenbrook Rd To B7031'),
        'A70--Glenbrook Rd To B7031',
      );
    });

    test('a picked option beats anything left in the free-text box', () {
      expect(
        resolvedChoice(selected: 'Example Road', typed: 'half-typed'),
        'Example Road',
      );
    });

    test('falls back to the typed text when the user chose "none of these"',
        () {
      expect(
        resolvedChoice(
          selected: '__not_listed__',
          typed: 'My Own Road',
          notListedValue: '__not_listed__',
        ),
        'My Own Road',
      );
    });

    test('never returns the not_listed_value the API sent', () {
      expect(
        resolvedChoice(
          selected: '__not_listed__',
          notListedValue: '__not_listed__',
        ),
        isNull,
      );
      expect(
        resolvedChoice(
          selected: '__not_listed__',
          typed: '   ',
          notListedValue: '__not_listed__',
        ),
        isNull,
      );
    });

    test('is null when nothing has been typed or picked', () {
      expect(resolvedChoice(), isNull);
      expect(resolvedChoice(selected: '  ', typed: ''), isNull);
    });
  });

  group('describeAddress', () {
    test('joins the parts the user gave, ending with the postcode', () {
      expect(
        describeAddress(
          postcode: 'CB4 2HX',
          property: '15 Example Court',
          street: 'Example Road',
          locality: 'Cambridge',
        ),
        '15 Example Court, Example Road, Cambridge, CB4 2HX',
      );
      expect(
        describeAddress(postcode: 'EH14 7AL', street: 'A70--Glenbrook Rd'),
        'A70--Glenbrook Rd, EH14 7AL',
      );
    });

    test('is just the postcode when the user gave no address text', () {
      expect(describeAddress(postcode: 'CB4 2HX'), 'CB4 2HX');
      expect(
        describeAddress(postcode: 'CB4 2HX', property: '  ', locality: null),
        'CB4 2HX',
      );
    });
  });

  group('PropertyTypes', () {
    test('offers exactly the four values the API accepts', () {
      expect(PropertyTypes.values, [
        'private_flat_without_bin_store',
        'private_block_with_bin_store',
        'housing_estate',
        'street_bag_collection',
      ]);
    });

    test('labels every value for the picker', () {
      for (final value in PropertyTypes.values) {
        expect(PropertyTypes.labelFor(value), isNotEmpty);
        expect(PropertyTypes.labelFor(value), isNot(value));
      }
    });

    test('falls back to the raw value for one it does not know', () {
      expect(PropertyTypes.labelFor('mansion'), 'mansion');
    });
  });

  group('weekdayNames', () {
    test('lists Monday to Sunday in order', () {
      expect(weekdayNames, [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]);
    });
  });
}

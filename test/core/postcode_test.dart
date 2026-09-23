import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/core/postcode.dart';

void main() {
  group('UkPostcode.isValid', () {
    test('accepts standard space-separated postcodes', () {
      expect(UkPostcode.isValid('CB4 2HX'), isTrue);
      expect(UkPostcode.isValid('SW1A 1AA'), isTrue);
      expect(UkPostcode.isValid('EH14 7AL'), isTrue);
      expect(UkPostcode.isValid('M1 1AE'), isTrue);
      expect(UkPostcode.isValid('DN55 1PT'), isTrue);
    });

    test('accepts a postcode with no space', () {
      expect(UkPostcode.isValid('CB42HX'), isTrue);
      expect(UkPostcode.isValid('SW1A1AA'), isTrue);
      expect(UkPostcode.isValid('EH147AL'), isTrue);
    });

    test('accepts lowercase and untidy whitespace', () {
      expect(UkPostcode.isValid('cb4 2hx'), isTrue);
      expect(UkPostcode.isValid('  CB4 2HX  '), isTrue);
      expect(UkPostcode.isValid('CB4  2HX'), isTrue);
    });

    test('accepts the Girobank postcode', () {
      expect(UkPostcode.isValid('GIR 0AA'), isTrue);
    });

    test('rejects an empty or blank value', () {
      expect(UkPostcode.isValid(''), isFalse);
      expect(UkPostcode.isValid('   '), isFalse);
    });

    test('rejects a value that is not a postcode shape', () {
      expect(UkPostcode.isValid('12345'), isFalse);
      expect(UkPostcode.isValid('CAMBRIDGE'), isFalse);
      expect(UkPostcode.isValid('CB4'), isFalse);
    });

    test('rejects a postcode missing its inward code', () {
      expect(UkPostcode.isValid('CB4 2H'), isFalse);
      expect(UkPostcode.isValid('CB4 '), isFalse);
      expect(UkPostcode.isValid('SW1A 1'), isFalse);
    });

    test('rejects a postcode that is too long', () {
      expect(UkPostcode.isValid('CB4 2HXY'), isFalse);
      expect(UkPostcode.isValid('CBB4 2HX'), isFalse);
    });
  });
}

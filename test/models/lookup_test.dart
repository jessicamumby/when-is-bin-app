import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/lookup.dart';

void main() {
  group('Lookup.fromJson', () {
    test('parses a done lookup with a result schedule', () {
      final json = {
        'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'status': 'done',
        'created_at': '2026-09-07T09:00:00Z',
        'completed_at': '2026-09-07T09:00:01Z',
        'council': {
          'id': 'E07000008',
          'name': 'Cambridge City Council',
        },
        'expected_wait_seconds': 8,
        'success_rate': 0.96,
        'result': {
          'property_id': 'p:4c5ee6c2f2c7c959',
          'address_match': 'exact',
          'collections': [
            {
              'name': 'Black bin',
              'waste_type': 'refuse',
              'dates': ['2026-09-10'],
            },
          ],
        },
      };

      final lookup = Lookup.fromJson(json);

      expect(lookup.id, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(lookup.status, 'done');
      expect(lookup.isTerminal, isTrue);
      expect(lookup.isPending, isFalse);
      expect(lookup.result?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(lookup.result?.collections, hasLength(1));
      expect(lookup.council?.name, 'Cambridge City Council');
      expect(lookup.expectedWaitSeconds, 8);
      expect(lookup.successRate, 0.96);
    });

    test('parses a queued lookup with progress and no result', () {
      final json = {
        'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'status': 'queued',
        'created_at': '2026-09-07T09:00:00Z',
        'council': {
          'id': 'E07000008',
          'name': 'Cambridge City Council',
        },
        'expected_wait_seconds': 120,
        'success_rate': 0.81,
        'progress': {
          'stage': 'deterministic',
          'message': "Checking the council's fastest sources",
        },
      };

      final lookup = Lookup.fromJson(json);

      expect(lookup.status, 'queued');
      expect(lookup.isPending, isTrue);
      expect(lookup.isTerminal, isFalse);
      expect(lookup.result, isNull);
      expect(lookup.progress?.stage, 'deterministic');
      expect(lookup.progress?.message, "Checking the council's fastest sources");
    });

    test('parses a failed lookup with a detail message', () {
      final json = {
        'id': 'abc',
        'status': 'failed',
        'detail': "The council's system doesn't list that exact address.",
      };

      final lookup = Lookup.fromJson(json);

      expect(lookup.status, 'failed');
      expect(lookup.isTerminal, isTrue);
      expect(lookup.detail, "The council's system doesn't list that exact address.");
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

void main() {
  const baseUrl = 'https://whenisbins.com/v1';

  WhenIsBinsApi buildApi(
    MockClient client, {
    String? token,
  }) {
    return WhenIsBinsApi(
      client: client,
      baseUrl: baseUrl,
      token: token,
    );
  }

  group('getAddresses', () {
    test('sends postcode query and returns an AddressLookup', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'postcode': 'CB4 2HX',
            'council': {
              'id': 'E07000008',
              'name': 'Cambridge City Council',
            },
            'required_input': 'property_id',
            'candidates': [
              {
                'id': 'p:4c5ee6c2f2c7c959',
                'label': '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final result = await api.getAddresses('CB4 2HX');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/addresses');
      expect(captured.url.queryParameters['postcode'], 'CB4 2HX');
      expect(result.postcode, 'CB4 2HX');
      expect(result.candidates, hasLength(1));
    });

    test('adds a bearer token header when configured', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'postcode': 'CB4 2HX',
            'required_input': 'none',
            'candidates': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client, token: 'secret-token');
      await api.getAddresses('CB4 2HX');

      expect(captured.headers['authorization'], 'Bearer secret-token');
    });

    test('throws an ApiException on a 404 outside coverage', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'problem': 'postcode_outside_coverage',
            'detail': 'Postcode is outside coverage.',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.getAddresses('ZZ99 9ZZ'),
        throwsA(isA<ApiException>()
            .having((e) => e.problem, 'problem', 'postcode_outside_coverage')
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('createLookup', () {
    test('POSTs the request body with an Idempotency-Key header', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
            'status': 'queued',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final lookup = await api.createLookup(
        {'postcode': 'CB4 2HX', 'property_id': 'p:4c5ee6c2f2c7c959'},
        idempotencyKey: '33f146d8-7ff4-4d1c-979d-8a5cb0441dd1',
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/lookups');
      expect(captured.headers['idempotency-key'],
          '33f146d8-7ff4-4d1c-979d-8a5cb0441dd1');
      expect(captured.headers['content-type'], 'application/json');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['postcode'], 'CB4 2HX');
      expect(body['property_id'], 'p:4c5ee6c2f2c7c959');
      expect(lookup.id, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(lookup.status, 'queued');
    });
  });

  group('getLookup', () {
    test('fetches a lookup snapshot by id', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
            'status': 'done',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final lookup = await api.getLookup('f47ac10b-58cc-4372-a567-0e02b2c3d479');

      expect(captured.method, 'GET');
      expect(captured.url.path,
          '/v1/lookups/f47ac10b-58cc-4372-a567-0e02b2c3d479');
      expect(lookup.status, 'done');
    });
  });

  group('getSchedule', () {
    test('fetches a schedule by property token', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'property_id': 'p:4c5ee6c2f2c7c959',
            'address_match': 'exact',
            'collections': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final schedule = await api.getSchedule('4c5ee6c2f2c7c959');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/schedules/4c5ee6c2f2c7c959');
      expect(schedule.propertyId, 'p:4c5ee6c2f2c7c959');
    });

    test('sends If-None-Match when an etag is provided', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'property_id': 'p:4c5ee6c2f2c7c959',
            'address_match': 'exact',
            'collections': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      await api.getSchedule('4c5ee6c2f2c7c959', etag: '"abc123"');

      expect(captured.headers['if-none-match'], '"abc123"');
    });
  });
}

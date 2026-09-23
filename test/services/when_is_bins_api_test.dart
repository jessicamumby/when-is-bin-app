import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

/// A client whose request never completes, like a socket that is accepted and
/// then left hanging.
class _HangingClient extends http.BaseClient {
  final _never = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _never.future;
}

void main() {
  const baseUrl = 'https://whenisbins.com/v1';

  WhenIsBinsApi buildApi(
    http.Client client, {
    String? token,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return WhenIsBinsApi(
      client: client,
      baseUrl: baseUrl,
      token: token,
      timeout: timeout,
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

  group('waitForLookup', () {
    test('long-polls the wait endpoint and returns the cursor and Retry-After',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'lookup-1',
            'status': 'partial',
            'progress': {'stage': 'council_site'},
            'result': {
              'property_id': 'p:4c5ee6c2f2c7c959',
              'address_match': 'exact',
              'collections': [],
            },
          }),
          200,
          headers: {
            'content-type': 'application/json',
            // The header name arrives in whatever case the server picked.
            'X-Lookup-Cursor': 'cur-2',
            'Retry-After': '7',
          },
        );
      });

      final api = buildApi(client);
      final wait = await api.waitForLookup('lookup-1', after: 'cur-1');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/lookups/lookup-1/wait');
      expect(captured.url.queryParameters['after'], 'cur-1');
      expect(wait.lookup.status, 'partial');
      expect(wait.lookup.progress?.stage, 'council_site');
      expect(wait.lookup.result?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(wait.cursor, 'cur-2');
      expect(wait.retryAfter, const Duration(seconds: 7));
    });

    test('omits the after parameter when there is no cursor', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'id': 'lookup-1', 'status': 'queued'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      await api.waitForLookup('lookup-1');

      expect(captured.url.queryParameters, isNot(contains('after')));
    });

    test('reports no wait when the server sends no Retry-After', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'id': 'lookup-1', 'status': 'running'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final wait = await api.waitForLookup('lookup-1');

      expect(wait.retryAfter, isNull);
    });

    test('ignores a Retry-After it cannot read, rather than stalling', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'id': 'lookup-1', 'status': 'running'}),
          200,
          headers: {
            'content-type': 'application/json',
            // An HTTP-date Retry-After is not a client-side duration we can
            // trust: fall back to the caller's own backoff.
            'Retry-After': 'Wed, 23 Sep 2026 12:00:00 GMT',
          },
        );
      });

      final api = buildApi(client);
      final wait = await api.waitForLookup('lookup-1');

      expect(wait.retryAfter, isNull);
    });

    test('surfaces an ApiException when the wait itself fails', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'problem': 'lookup_not_found',
            'detail': 'No such lookup.',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.waitForLookup('lookup-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.problem, 'problem', 'lookup_not_found')
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('checkSchedule', () {
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
          headers: {
            'content-type': 'application/json',
            'ETag': '"v1-abc123"',
          },
        );
      });

      final api = buildApi(client);
      final check = await api.checkSchedule('4c5ee6c2f2c7c959');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/schedules/4c5ee6c2f2c7c959');
      expect(captured.headers, isNot(contains('if-none-match')));
      expect(check.updated, isTrue);
      expect(check.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(check.etag, '"v1-abc123"');
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
      await api.checkSchedule('4c5ee6c2f2c7c959', etag: '"abc123"');

      expect(captured.headers['if-none-match'], '"abc123"');
    });

    test('treats a 304 as unchanged and keeps the etag we sent', () async {
      final client = MockClient((request) async {
        return http.Response('', 304);
      });

      final api = buildApi(client);
      final check = await api.checkSchedule('4c5ee6c2f2c7c959',
          etag: '"abc123"');

      expect(check.unchanged, isTrue);
      expect(check.updated, isFalse);
      expect(check.missing, isFalse);
      expect(check.schedule, isNull);
      expect(check.etag, '"abc123"');
    });

    test('uses the etag a 200 hands back', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'property_id': 'p:4c5ee6c2f2c7c959',
            'address_match': 'exact',
            'collections': [],
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'etag': '"v2-def456"',
          },
        );
      });

      final api = buildApi(client);
      final check =
          await api.checkSchedule('4c5ee6c2f2c7c959', etag: '"v1-abc123"');

      expect(check.updated, isTrue);
      expect(check.etag, '"v2-def456"');
    });

    test('treats a 404 no_schedule as missing rather than an error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'problem': 'no_schedule',
            'detail': 'No schedule has been recorded for this property.',
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);
      final check = await api.checkSchedule('4c5ee6c2f2c7c959');

      expect(check.missing, isTrue);
      expect(check.updated, isFalse);
      expect(check.unchanged, isFalse);
    });

    test('still throws for a genuine server error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'problem': 'rate_limited'}),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.checkSchedule('4c5ee6c2f2c7c959'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
    });
  });

  group('malformed responses', () {
    test('surfaces an ApiException for an HTML body on a 429', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<html><body>Too many requests</body></html>',
          429,
          headers: {'content-type': 'text/html'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.getAddresses('CB4 2HX'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.detail, 'detail',
                WhenIsBinsApi.unexpectedResponseDetail)),
      );
    });

    test('surfaces an ApiException for a plain-text 502', () async {
      final client = MockClient((request) async {
        return http.Response(
          'Bad gateway',
          502,
          headers: {'content-type': 'text/plain'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.getLookup('lookup-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.detail, 'detail',
                WhenIsBinsApi.unexpectedResponseDetail)),
      );
    });

    test('never leaks a FormatException', () async {
      final client = MockClient((request) async {
        return http.Response('<!DOCTYPE html>', 500);
      });

      final api = buildApi(client);

      try {
        await api.getAddresses('CB4 2HX');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 500);
      } on FormatException catch (e) {
        fail('leaked a FormatException: $e');
      }
    });

    test('keeps the problem and detail from a JSON error body', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'problem': 'rate_limited',
            'detail': 'Slow down.',
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = buildApi(client);

      expect(
        () => api.getAddresses('CB4 2HX'),
        throwsA(isA<ApiException>()
            .having((e) => e.problem, 'problem', 'rate_limited')
            .having((e) => e.detail, 'detail', 'Slow down.')),
      );
    });

    test('surfaces an ApiException for a 2xx with a malformed body', () async {
      final client = MockClient((request) async {
        return http.Response('<html>Welcome</html>', 200);
      });

      final api = buildApi(client);

      expect(
        () => api.getLookup('lookup-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.problem, 'problem', 'invalid_response')
            .having((e) => e.detail, 'detail',
                WhenIsBinsApi.unexpectedResponseDetail)),
      );
    });

    test('surfaces an ApiException for an empty 5xx body', () async {
      final client = MockClient((request) async {
        return http.Response('', 503);
      });

      final api = buildApi(client);

      expect(
        () => api.createLookup({'postcode': 'CB4 2HX'}, idempotencyKey: 'k'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.detail, 'detail',
                WhenIsBinsApi.unexpectedResponseDetail)),
      );
    });

    test('surfaces an ApiException for JSON that is not an object', () async {
      final client = MockClient((request) async {
        return http.Response('["not","an","object"]', 200);
      });

      final api = buildApi(client);

      expect(
        () => api.getLookup('lookup-1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('timeouts', () {
    test('defaults to a 15 second deadline', () {
      final api = buildApi(MockClient((request) async => http.Response('{}', 200)));

      expect(api.timeout, const Duration(seconds: 15));
    });

    test('turns a hung request into an ApiException', () async {
      final api = buildApi(
        _HangingClient(),
        timeout: const Duration(milliseconds: 20),
      );

      expect(
        () => api.getLookup('lookup-1'),
        throwsA(isA<ApiException>()
            .having((e) => e.problem, 'problem', 'timeout')
            .having((e) => e.statusCode, 'statusCode', 0)),
      );
    });

    test('turns a dropped connection into an ApiException', () async {
      final client = MockClient((request) async {
        throw http.ClientException('Connection closed before full header');
      });

      final api = buildApi(client);

      expect(
        () => api.getAddresses('CB4 2HX'),
        throwsA(isA<ApiException>()
            .having((e) => e.problem, 'problem', 'network')),
      );
    });
  });
}

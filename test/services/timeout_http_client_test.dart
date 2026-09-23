import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:when_is_bin_app/services/timeout_http_client.dart';

/// A client whose request never completes, like a socket that is accepted and
/// then left hanging.
class _HangingClient extends http.BaseClient {
  final _never = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _never.future;
}

/// Records [close] so the wrapper can be shown to close what it wrapped.
class _RecordingClient extends http.BaseClient {
  int closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

void main() {
  group('TimeoutHttpClient', () {
    test('gives every request a deadline', () async {
      final client = TimeoutHttpClient(
        _HangingClient(),
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.get(Uri.parse('https://whenisbins.com/v1/lookups/1/wait')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('leaves a responsive request alone', () async {
      final inner = MockClient(
        (request) async => http.Response('{"id":"lookup-1"}', 200),
      );
      final client = TimeoutHttpClient(inner);

      final response =
          await client.get(Uri.parse('https://whenisbins.com/v1/addresses'));

      expect(response.statusCode, 200);
      expect(response.body, '{"id":"lookup-1"}');
    });

    test('closes the client it wraps', () {
      final inner = _RecordingClient();

      TimeoutHttpClient(inner).close();

      expect(inner.closeCalls, 1);
    });
  });
}

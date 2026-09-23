import 'dart:async';

import 'package:http/http.dart' as http;

/// An [http.Client] that puts a deadline on every request.
///
/// Nothing in `package:http` times out by default, so a socket that is
/// accepted and then left silent (a flaky mobile network, a proxy that hangs)
/// leaves the UI waiting for ever. This wrapper turns that into a
/// [TimeoutException] the caller can handle.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(
    this._inner, {
    this.timeout = const Duration(seconds: 15),
  });

  final http.Client _inner;

  /// The deadline for a single request.
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }

  @override
  void close() => _inner.close();
}

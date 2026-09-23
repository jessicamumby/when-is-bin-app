import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/address_lookup.dart';
import '../models/lookup.dart';
import '../models/schedule.dart';

/// An error returned by the WhenIsBins API.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    this.problem,
    this.detail,
  });

  final int statusCode;
  final String? problem;
  final String? detail;

  @override
  String toString() => 'ApiException($statusCode, $problem, $detail)';
}

/// One answer from a `GET /lookups/{id}/wait` long-poll.
///
/// The lookup itself, plus the bits of the response the client has to act on
/// when it reconnects: the cursor to send back, and any wait the server asked
/// for.
class LookupWait {
  const LookupWait({
    required this.lookup,
    this.cursor,
    this.retryAfter,
  });

  final Lookup lookup;

  /// The `X-Lookup-Cursor` header, to be sent as `after` on the next wait.
  final String? cursor;

  /// The `Retry-After` header as a duration, when the server sent one we can
  /// read.
  final Duration? retryAfter;
}

/// The outcome of a conditional `GET /schedules/{token}`.
///
/// A 304 carries no body, and a 404 `no_schedule` is a fact about the property
/// rather than a failure, so neither can be expressed by returning a
/// [Schedule] and throwing on everything else.
class ScheduleCheck {
  const ScheduleCheck.updated(Schedule schedule, {this.etag})
      : schedule = schedule,
        unchanged = false,
        missing = false;

  /// The server confirmed the cached copy is still current (304).
  const ScheduleCheck.unchanged({this.etag})
      : schedule = null,
        unchanged = true,
        missing = false;

  /// The council has never answered for this property (404 `no_schedule`).
  const ScheduleCheck.missing()
      : schedule = null,
        etag = null,
        unchanged = false,
        missing = true;

  /// The fresh schedule, on an [updated] answer.
  final Schedule? schedule;

  /// The ETag to send back as `If-None-Match` next time.
  final String? etag;

  final bool unchanged;
  final bool missing;

  bool get updated => schedule != null;
}

/// Client for the WhenIsBins UK bin collection API (`/v1`).
class WhenIsBinsApi {
  WhenIsBinsApi({
    required http.Client client,
    required this.baseUrl,
    this.token,
    this.timeout = defaultTimeout,
  }) : _client = client;

  /// How long a single request may take before it is abandoned.
  static const defaultTimeout = Duration(seconds: 15);

  /// What the user is told when the server answers with something this client
  /// cannot read: a rate limiter page, a gateway error, a truncated body.
  static const unexpectedResponseDetail = 'Unexpected response from the server';

  /// The `problem` on an [ApiException] raised for a body that is not JSON.
  static const invalidResponseProblem = 'invalid_response';

  /// The `problem` on an [ApiException] raised when a request never answered.
  static const timeoutProblem = 'timeout';

  /// The `problem` on an [ApiException] raised when the connection failed.
  static const networkProblem = 'network';

  final http.Client _client;
  final String baseUrl;
  final String? token;

  /// The deadline for a single request. Without it a hung network call leaves
  /// the app loading for ever.
  final Duration timeout;

  /// Resolve a postcode to its council and required address input.
  Future<AddressLookup> getAddresses(String postcode, {String? q}) async {
    final uri = Uri.parse('$baseUrl/addresses').replace(
      queryParameters: {
        'postcode': postcode,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final response = await _send(() => _client.get(uri, headers: _headers()));
    return AddressLookup.fromJson(_decode(response));
  }

  /// Start (or immediately satisfy) a property lookup.
  Future<Lookup> createLookup(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async {
    final response = await _send(() => _client.post(
          Uri.parse('$baseUrl/lookups'),
          headers: _headers()..['idempotency-key'] = idempotencyKey,
          body: jsonEncode(body),
        ));
    return Lookup.fromJson(_decode(response));
  }

  /// Fetch one snapshot of a lookup.
  Future<Lookup> getLookup(String lookupId) async {
    final response = await _send(() => _client.get(
          Uri.parse('$baseUrl/lookups/$lookupId'),
          headers: _headers(),
        ));
    return Lookup.fromJson(_decode(response));
  }

  /// Long-poll a lookup until it changes or the server's wait budget runs out.
  ///
  /// The server holds the request open (roughly 25s) so this is far cheaper
  /// than snapshotting, but it means only one wait may be open per lookup: the
  /// caller reconnects with the [LookupWait.cursor] from the previous answer
  /// and waits out any [LookupWait.retryAfter] first.
  Future<LookupWait> waitForLookup(String lookupId, {String? after}) async {
    final uri = Uri.parse('$baseUrl/lookups/$lookupId/wait').replace(
      queryParameters: {
        if (after != null && after.isNotEmpty) 'after': after,
      },
    );
    final response = await _send(() => _client.get(uri, headers: _headers()));
    return LookupWait(
      lookup: Lookup.fromJson(_decode(response)),
      cursor: _header(response, 'x-lookup-cursor'),
      retryAfter: _retryAfter(response),
    );
  }

  /// Re-check a property's schedule, conditionally when an [etag] is known.
  ///
  /// 200 is a fresh schedule with its new ETag, 304 means the cached copy is
  /// still current, and 404 `no_schedule` means the council has never answered
  /// for this property.
  Future<ScheduleCheck> checkSchedule(
    String propertyToken, {
    String? etag,
  }) async {
    final response = await _send(() => _client.get(
          Uri.parse('$baseUrl/schedules/$propertyToken'),
          headers: {
            ..._headers(),
            if (etag != null && etag.isNotEmpty) 'if-none-match': etag,
          },
        ));
    if (response.statusCode == 304) {
      // Nothing changed: the tag we sent is still the current one.
      return ScheduleCheck.unchanged(
        etag: _header(response, 'etag') ?? etag,
      );
    }
    if (response.statusCode == 404) {
      return const ScheduleCheck.missing();
    }
    return ScheduleCheck.updated(
      Schedule.fromJson(_decode(response)),
      etag: _header(response, 'etag') ?? etag,
    );
  }

  Map<String, String> _headers() {
    return {
      'accept': 'application/json',
      'content-type': 'application/json',
      if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  /// Run a request with the configured deadline, turning transport failures
  /// into [ApiException]s so callers only ever handle one error type.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        problem: timeoutProblem,
        detail: 'The server took too long to respond. Please try again.',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        statusCode: 0,
        problem: networkProblem,
        detail: e.message,
      );
    }
  }

  /// The status code decides success or failure; the body is only ever read
  /// afterwards. A rate limiter or a gateway answering with HTML is a normal
  /// failure, not a crash.
  Map<String, dynamic> _decode(http.Response response) {
    final body = _tryDecodeObject(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body == null) {
        throw ApiException(
          statusCode: response.statusCode,
          problem: invalidResponseProblem,
          detail: unexpectedResponseDetail,
        );
      }
      return body;
    }
    throw ApiException(
      statusCode: response.statusCode,
      problem: body?['problem'] as String?,
      detail: (body?['detail'] as String?) ?? unexpectedResponseDetail,
    );
  }

  /// The body decoded as a JSON object, or null when it is empty, not JSON, or
  /// JSON of some other shape.
  Map<String, dynamic>? _tryDecodeObject(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Header lookup by lowercase name: `package:http` lowercases the headers a
  /// real server sends but passes test doubles through untouched.
  String? _header(http.Response response, String name) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  /// `Retry-After` in seconds. The HTTP-date form is not a duration this
  /// client can honour, so it is reported as "no wait asked for" and the
  /// caller falls back to its own backoff.
  Duration? _retryAfter(http.Response response) {
    final raw = _header(response, 'retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }
}

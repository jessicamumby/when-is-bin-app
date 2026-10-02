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
    this.retryAfter,
  });

  final int statusCode;
  final String? problem;
  final String? detail;

  /// How long the server asked the caller to wait before retrying, from a
  /// `Retry-After` response header. Null when the server sent none (or sent a
  /// form this client cannot read), in which case the caller falls back to its
  /// own backoff.
  final Duration? retryAfter;

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
    this.waitTimeout = defaultWaitTimeout,
  }) : _client = client;

  /// How long a single request may take before it is abandoned.
  static const defaultTimeout = Duration(seconds: 15);

  /// The deadline for `GET /lookups/{id}/wait`, which the server deliberately
  /// holds open (roughly 25s) before it answers. It must stay comfortably
  /// above that hold time, so it is much longer than [defaultTimeout].
  static const defaultWaitTimeout = Duration(seconds: 40);

  /// What the user is told when the server answers with something this client
  /// cannot read: a rate limiter page, a gateway error, a truncated body.
  static const unexpectedResponseDetail = 'Unexpected response from the server';

  /// The `problem` on an [ApiException] raised for a body that is not JSON.
  static const invalidResponseProblem = 'invalid_response';

  /// The `problem` on an [ApiException] raised when a request never answered.
  static const timeoutProblem = 'timeout';

  /// The `problem` on an [ApiException] raised when the connection failed.
  static const networkProblem = 'network';

  /// The prefix `property_id` values carry. Paths want the bare token.
  static const _propertyIdPrefix = 'p:';

  final http.Client _client;
  final String baseUrl;
  final String? token;

  /// The deadline for a single request. Without it a hung network call leaves
  /// the app loading for ever.
  final Duration timeout;

  /// The deadline for `/wait` requests. The server holds those open far longer
  /// than a normal request, so they get their own budget.
  final Duration waitTimeout;

  /// Resolve a postcode to its council and required address input.
  Future<AddressLookup> getAddresses(String postcode, {String? q}) async {
    final uri = Uri.parse('$baseUrl/addresses').replace(
      queryParameters: {
        'postcode': postcode,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final response = await _send(() => _client.get(uri, headers: _headers()));
    return _parse(response, AddressLookup.fromJson);
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
    return _parse(response, Lookup.fromJson);
  }

  /// Fetch one snapshot of a lookup.
  Future<Lookup> getLookup(String lookupId) async {
    final response = await _send(() => _client.get(
          Uri.parse('$baseUrl/lookups/$lookupId'),
          headers: _headers(),
        ));
    return _parse(response, Lookup.fromJson);
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
    final response = await _send(
      () => _client.get(uri, headers: _headers()),
      timeout: waitTimeout,
    );
    return LookupWait(
      lookup: _parse(response, Lookup.fromJson),
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
    // A `property_id` (and so the id the app saves) keeps its `p:` prefix, but
    // the schedules path wants the bare token: sending the prefixed form only
    // worked because the API answered a 301, costing a second request on every
    // launch check.
    final token = propertyToken.startsWith(_propertyIdPrefix)
        ? propertyToken.substring(_propertyIdPrefix.length)
        : propertyToken;
    final response = await _send(() => _client.get(
          Uri.parse('$baseUrl/schedules/$token'),
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
      _parse(response, Schedule.fromJson),
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
  ///
  /// The `timeout` argument overrides the client-wide [timeout] for one call,
  /// for the endpoints that need their own budget (only `/wait` does).
  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    try {
      return await request().timeout(timeout ?? this.timeout);
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
    } on ApiException {
      rethrow;
    } catch (e) {
      // Anything else the transport throws (a failed TLS handshake, a socket
      // error the client did not wrap) is still a failed connection, and must
      // reach the caller as one so the user is told something.
      throw ApiException(
        statusCode: 0,
        problem: networkProblem,
        detail: e.toString(),
      );
    }
  }

  /// Decode [response] and build a model from it. A body that is JSON but not
  /// the shape the model expects is an unreadable answer, not a crash.
  T _parse<T>(
    http.Response response,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final body = _decode(response);
    try {
      return fromJson(body);
    } catch (_) {
      throw ApiException(
        statusCode: response.statusCode,
        problem: invalidResponseProblem,
        detail: unexpectedResponseDetail,
      );
    }
  }

  /// The status code decides success or failure; the body is only ever read
  /// afterwards. A rate limiter or a gateway answering with HTML is a normal
  /// failure, not a crash.
  Map<String, dynamic> _decode(http.Response response) {
    final body = _tryDecodeObject(response);
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
      // A 429 tells the caller how long to wait; discarding it here forced
      // every caller to guess and retry too soon.
      retryAfter: _retryAfter(response),
    );
  }

  /// The body decoded as a JSON object, or null when it is empty, not JSON,
  /// not valid text in its declared encoding, or JSON of some other shape.
  Map<String, dynamic>? _tryDecodeObject(http.Response response) {
    try {
      // Reading `body` decodes the bytes, which throws on malformed UTF-8.
      final body = response.body;
      if (body.trim().isEmpty) return null;
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

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

/// Client for the WhenIsBins UK bin collection API (`/v1`).
class WhenIsBinsApi {
  WhenIsBinsApi({
    required http.Client client,
    required this.baseUrl,
    this.token,
  }) : _client = client;

  final http.Client _client;
  final String baseUrl;
  final String? token;

  /// Resolve a postcode to its council and required address input.
  Future<AddressLookup> getAddresses(String postcode, {String? q}) async {
    final uri = Uri.parse('$baseUrl/addresses').replace(
      queryParameters: {
        'postcode': postcode,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final response = await _client.get(uri, headers: _headers());
    return AddressLookup.fromJson(_decode(response));
  }

  /// Start (or immediately satisfy) a property lookup.
  Future<Lookup> createLookup(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/lookups'),
      headers: _headers()..['idempotency-key'] = idempotencyKey,
      body: jsonEncode(body),
    );
    return Lookup.fromJson(_decode(response));
  }

  /// Fetch one snapshot of a lookup.
  Future<Lookup> getLookup(String lookupId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/lookups/$lookupId'),
      headers: _headers(),
    );
    return Lookup.fromJson(_decode(response));
  }

  /// Retrieve the stable address-free schedule for a property token.
  Future<Schedule> getSchedule(String propertyToken, {String? etag}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/schedules/$propertyToken'),
      headers: _headers()
        ..remove('if-none-match')
        ..addAll(etag == null ? {} : {'if-none-match': etag}),
    );
    return Schedule.fromJson(_decode(response));
  }

  Map<String, String> _headers() {
    return {
      'accept': 'application/json',
      'content-type': 'application/json',
      if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw ApiException(
      statusCode: response.statusCode,
      problem: body['problem'] as String?,
      detail: body['detail'] as String?,
    );
  }
}

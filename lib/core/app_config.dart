import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loads app configuration from `.env`.
class AppConfig {
  AppConfig._();

  static const _defaultBaseUrl = 'https://whenisbins.com/v1';

  /// The WhenIsBins API base URL.
  static String get baseUrl {
    final v = dotenv.env['WHENISBINS_BASE_URL'];
    return (v == null || v.isEmpty) ? _defaultBaseUrl : v;
  }

  /// The bearer token for the WhenIsBins API, or null if not configured.
  static String? get apiToken {
    final v = dotenv.env['WHENISBINS_API_TOKEN'];
    return (v == null || v.isEmpty) ? null : v;
  }
}

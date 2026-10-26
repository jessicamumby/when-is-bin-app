import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/core/app_config.dart';

void main() {
  group('AppConfig', () {
    test('reads the shipped .env.example as anonymous use of the live API',
        () {
      // Store and CI builds bundle exactly this file (`cp .env.example .env`),
      // so it must parse to no token and the whenisbins.com base URL.
      dotenv.testLoad(fileInput: File('.env.example').readAsStringSync());

      expect(AppConfig.apiToken, isNull);
      expect(Uri.parse(AppConfig.baseUrl).host, 'whenisbins.com');
    });

    test('empty values fall back to the default URL and no token', () {
      dotenv.testLoad(
        fileInput: 'WHENISBINS_BASE_URL=\nWHENISBINS_API_TOKEN=\n',
      );

      expect(AppConfig.baseUrl, 'https://whenisbins.com/v1');
      expect(AppConfig.apiToken, isNull);
    });

    test('passes a configured token through', () {
      dotenv.testLoad(fileInput: 'WHENISBINS_API_TOKEN=not-a-real-token\n');

      expect(AppConfig.apiToken, 'not-a-real-token');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/core/api_error_copy.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

void main() {
  group('apiErrorCopy', () {
    test('a failed connection reads as being offline, never the system text',
        () {
      const error = ApiException(
        statusCode: 0,
        problem: WhenIsBinsApi.networkProblem,
        detail: "Failed host lookup: 'whenisbins.com'",
      );

      final copy = apiErrorCopy(error);

      expect(copy, 'You\u2019re offline. Check your connection and try again.');
      expect(copy, isNot(contains('Failed host lookup')));
    });

    test('a timeout tells the user to check their connection', () {
      const error = ApiException(
        statusCode: 0,
        problem: WhenIsBinsApi.timeoutProblem,
        detail: 'TimeoutException after 0:00:15.000000',
      );

      expect(
        apiErrorCopy(error),
        'That took too long. Check your connection and try again.',
      );
    });

    test('any other problem still falls back to the API detail', () {
      const error = ApiException(
        statusCode: 404,
        problem: 'something_new',
        detail: 'A message from the API.',
      );

      expect(apiErrorCopy(error), 'A message from the API.');
    });
  });
}

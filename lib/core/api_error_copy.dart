import '../services/when_is_bins_api.dart';

/// What to say when the API refuses a request.
///
/// The API's own `detail` is written for whoever is reading the wire — a
/// rate-limit answer talks about network-address allowances and wait tokens,
/// which is the server's accounting, not the user's problem. The failures a
/// user can actually act on get their own plain-English line here; anything
/// else falls back to the API's `detail`.
String apiErrorCopy(ApiException e) {
  switch (e.problem) {
    case 'rate_limited':
      return 'Lots of people are checking bin days right now. '
          'Try again in a minute.';
    case 'postcode_outside_coverage':
      return 'We could not find a collecting council for that postcode.';
    case 'invalid_postcode':
      return 'Enter a full UK postcode.';
    default:
      return e.detail ?? 'Something went wrong. Please try again.';
  }
}

/// The line that follows a rate-limited message: how long the server asked
/// the app to wait, in the plainest terms it can honestly give.
///
/// Null when the server sent no `Retry-After` — a made-up countdown would be
/// worse than no countdown. Seconds are rounded up, and never reported as
/// zero: "in about 0 seconds" reads as "now".
String? apiRetryAfterCopy(Duration? retryAfter) {
  if (retryAfter == null) return null;
  final seconds = (retryAfter.inMilliseconds / 1000).ceil();
  return 'Try again in about ${seconds < 1 ? 1 : seconds} seconds';
}

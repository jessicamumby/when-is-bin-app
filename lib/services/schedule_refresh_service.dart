import '../models/schedule.dart';
import 'when_is_bins_api.dart';

/// What a re-check of a saved schedule found.
enum ScheduleRefreshStatus {
  /// The server confirmed the cached copy is still current.
  unchanged,

  /// A newer schedule came back and should replace the cached one.
  updated,

  /// The council has never answered for this property (`404 no_schedule`).
  missing,

  /// The check could not be completed; the cached copy stands.
  failed,
}

/// The outcome of a re-check, always carrying the schedule to use now.
class ScheduleRefreshResult {
  const ScheduleRefreshResult({
    required this.status,
    required this.schedule,
    this.etag,
  });

  final ScheduleRefreshStatus status;

  /// The schedule to show: the refreshed one, or the cached one when there was
  /// nothing newer to apply.
  final Schedule? schedule;

  /// The ETag to store for the next conditional check.
  final String? etag;

  bool get isUpdated => status == ScheduleRefreshStatus.updated;
}

/// Re-checks a saved schedule against the API.
///
/// The schedule on the phone is only as fresh as the last lookup, and a
/// council can move a collection day in between, so the saved copy is
/// re-checked with a conditional request (`If-None-Match`) instead of being
/// looked up again. A 304 costs the user nothing.
class ScheduleRefreshService {
  ScheduleRefreshService({required WhenIsBinsApi api}) : _api = api;

  final WhenIsBinsApi _api;

  /// Ask whether [cached] is still current for [propertyToken].
  ///
  /// Never throws: a re-check happens on launch, and neither a rate limit nor
  /// a dead connection may stop the app from starting or blank the bin days
  /// already on the phone. Anything unexpected leaves [cached] in place.
  Future<ScheduleRefreshResult> refresh({
    required String propertyToken,
    required Schedule cached,
    String? etag,
  }) async {
    try {
      final check = await _api.checkSchedule(propertyToken, etag: etag);
      if (check.unchanged) {
        return ScheduleRefreshResult(
          status: ScheduleRefreshStatus.unchanged,
          schedule: cached,
          etag: check.etag ?? etag,
        );
      }
      if (check.missing) {
        return ScheduleRefreshResult(
          status: ScheduleRefreshStatus.missing,
          schedule: cached,
          etag: etag,
        );
      }
      return ScheduleRefreshResult(
        status: ScheduleRefreshStatus.updated,
        schedule: check.schedule,
        etag: check.etag ?? etag,
      );
    } on ApiException {
      return ScheduleRefreshResult(
        status: ScheduleRefreshStatus.failed,
        schedule: cached,
        etag: etag,
      );
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/services/schedule_refresh_service.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../fakes/fake_api.dart';

Schedule cachedSchedule() {
  return const Schedule(
    propertyId: 'p:4c5ee6c2f2c7c959',
    addressMatch: 'exact',
    collections: [
      Collection(
        name: 'Black bin',
        wasteType: 'refuse',
        dates: ['2026-09-10'],
      ),
    ],
  );
}

/// The same property with the collection day moved by a week.
Schedule movedSchedule() {
  return const Schedule(
    propertyId: 'p:4c5ee6c2f2c7c959',
    addressMatch: 'exact',
    collections: [
      Collection(
        name: 'Black bin',
        wasteType: 'refuse',
        dates: ['2026-09-17'],
      ),
    ],
  );
}

void main() {
  group('ScheduleRefreshService', () {
    test('checks the schedule with the stored etag', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = const ScheduleCheck.unchanged(etag: '"v1"');
      final service = ScheduleRefreshService(api: api);

      await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
        etag: '"v1"',
      );

      expect(api.scheduleCheckCalls, 1);
      expect(api.lastScheduleToken, '4c5ee6c2f2c7c959');
      expect(api.lastScheduleEtag, '"v1"');
    });

    test('checks without a conditional header when no etag is known', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = ScheduleCheck.updated(movedSchedule(), etag: '"v1"');
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
      );

      expect(api.lastScheduleEtag, isNull);
      expect(result.status, ScheduleRefreshStatus.updated);
      expect(result.etag, '"v1"');
    });

    test('keeps the cached schedule when the server says unchanged', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = const ScheduleCheck.unchanged(etag: '"v1"');
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
        etag: '"v1"',
      );

      expect(result.status, ScheduleRefreshStatus.unchanged);
      expect(result.schedule?.collections.single.dates, ['2026-09-10']);
      expect(result.etag, '"v1"');
    });

    test('applies a changed schedule with its new etag', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = ScheduleCheck.updated(movedSchedule(), etag: '"v2"');
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
        etag: '"v1"',
      );

      expect(result.status, ScheduleRefreshStatus.updated);
      expect(result.schedule?.collections.single.dates, ['2026-09-17'],
          reason: 'a moved collection day must reach the user');
      expect(result.etag, '"v2"');
    });

    test('keeps the cached schedule when the council has no schedule', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheck = const ScheduleCheck.missing();
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
      );

      expect(result.status, ScheduleRefreshStatus.missing);
      expect(result.schedule?.collections.single.dates, ['2026-09-10'],
          reason: 'a 404 must not blank the bin days already on the phone');
    });

    test('never throws when the API fails', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheckError = const ApiException(
          statusCode: 429,
          problem: 'rate_limited',
          detail: 'Slow down.',
        );
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
        etag: '"v1"',
      );

      expect(result.status, ScheduleRefreshStatus.failed);
      expect(result.schedule?.collections.single.dates, ['2026-09-10']);
      expect(result.etag, '"v1"');
    });

    test('never throws when the connection drops', () async {
      final api = FakeWhenIsBinsApi()
        ..scheduleCheckError = const ApiException(
          statusCode: 0,
          problem: WhenIsBinsApi.networkProblem,
          detail: 'Connection closed',
        );
      final service = ScheduleRefreshService(api: api);

      final result = await service.refresh(
        propertyToken: '4c5ee6c2f2c7c959',
        cached: cachedSchedule(),
      );

      expect(result.status, ScheduleRefreshStatus.failed);
      expect(result.schedule, isNotNull);
    });
  });
}

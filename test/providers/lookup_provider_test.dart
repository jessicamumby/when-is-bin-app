import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/address_lookup.dart';
import 'package:when_is_bin_app/models/lookup.dart';
import 'package:when_is_bin_app/models/schedule.dart';
import 'package:when_is_bin_app/providers/lookup_provider.dart';
import 'package:when_is_bin_app/services/when_is_bins_api.dart';

import '../fakes/fake_api.dart';

const _candidate = AddressCandidate(
  id: 'p:4c5ee6c2f2c7c959',
  label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
);

void main() {
  group('LookupProvider', () {
    test('starts empty', () {
      final provider = LookupProvider(api: FakeWhenIsBinsApi());

      expect(provider.postcode, isNull);
      expect(provider.addressLookup, isNull);
      expect(provider.schedule, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('lookupPostcode resolves the address and clears error', () async {
      final api = FakeWhenIsBinsApi()
        ..addressLookup = AddressLookup(
          postcode: 'CB4 2HX',
          requiredInput: 'property_id',
          candidates: const [
            AddressCandidate(
              id: 'p:4c5ee6c2f2c7c959',
              label: '15 EXAMPLE COURT, CAMBRIDGE, CB4 2HX',
            ),
          ],
        );
      final provider = LookupProvider(api: api);

      await provider.lookupPostcode('CB4 2HX');

      expect(provider.postcode, 'CB4 2HX');
      expect(provider.addressLookup?.candidates, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('lookupPostcode surfaces an ApiException as error', () async {
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 404,
          problem: 'postcode_outside_coverage',
          detail: 'Postcode is outside coverage.',
        );
      final provider = LookupProvider(api: api);

      await provider.lookupPostcode('ZZ99 9ZZ');

      expect(provider.error?.problem, 'postcode_outside_coverage');
      expect(provider.addressLookup, isNull);
    });

    test('selectAddress creates a lookup and waits until done', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'queued',
            expectedWaitSeconds: 1,
          ),
        ]
        ..waitResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'done',
            result: Schedule(
              propertyId: 'p:4c5ee6c2f2c7c959',
              addressMatch: 'exact',
              collections: const [
                Collection(
                  name: 'Black bin',
                  wasteType: 'refuse',
                  dates: ['2026-09-10'],
                ),
              ],
            ),
          ),
        ];
      final provider = LookupProvider(api: api);

      await provider.selectAddress(_candidate, postcode: 'CB4 2HX');

      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.schedule?.collections, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('selectAddress surfaces a failed lookup detail', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'failed',
            detail: "The council's system doesn't list that exact address.",
          ),
        ];
      final provider = LookupProvider(api: api);

      await provider.selectAddress(
        const AddressCandidate(id: 'p:abc', label: '1 Test Road'),
        postcode: 'CB4 2HX',
      );

      expect(provider.schedule, isNull);
      expect(provider.error?.detail,
          "The council's system doesn't list that exact address.");
      expect(provider.pendingLookupId, isNull);
    });

    test('selectAddress sends a valid idempotency key (visible ASCII, no spaces)',
            () async {
          final api = FakeWhenIsBinsApi()
            ..addressLookup = AddressLookup(
              postcode: 'CB4 2HX',
              requiredInput: 'property_id',
              candidates: const [
                AddressCandidate(id: 'p:abc', label: '1 Test Road'),
              ],
            )
            ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done')];
          final provider = LookupProvider(api: api);

          // Real flow: postcode is resolved first, so _postcode holds a value
          // containing a space (e.g. 'CB4 2HX') when the lookup is submitted.
          await provider.lookupPostcode('CB4 2HX');
          await provider.selectAddress(
            const AddressCandidate(id: 'p:abc', label: '1 Test Road'),
            postcode: 'CB4 2HX',
          );

          final key = api.lastIdempotencyKey!;
          // The WhenIsBins API requires 1-128 visible ASCII characters.
          expect(key.length, inInclusiveRange(1, 128));
          expect(key, isNot(contains(RegExp(r'\s'))),
              reason: 'Idempotency-Key must not contain whitespace');
          expect(RegExp(r'^[\x21-\x7E]+$').hasMatch(key), isTrue,
              reason: 'Idempotency-Key must be visible ASCIISCII only');
        });
  });

  group('LookupProvider long-polling', () {
    late DateTime now;
    late List<Duration> slept;

    setUp(() {
      now = DateTime(2026, 9, 23, 12);
      slept = [];
    });

    /// A clock that advances by exactly what the provider asks to sleep, so
    /// the two-minute budget is exercised without waiting two minutes.
    Future<void> delay(Duration duration) async {
      slept.add(duration);
      now = now.add(duration);
    }

    LookupProvider buildProvider(
      FakeWhenIsBinsApi api, {
      Duration maxWait = const Duration(minutes: 2),
    }) {
      return LookupProvider(
        api: api,
        delay: delay,
        now: () => now,
        maxWait: maxWait,
      );
    }

    Schedule pollSchedule() {
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

    Future<void> select(LookupProvider provider) {
      return provider.selectAddress(_candidate, postcode: 'CB4 2HX');
    }

    test('waits on the endpoint instead of snapshotting every second',
        () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'done', result: pollSchedule()),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(api.waitCallCount, 1);
      expect(api.lookupCallCount, 0,
          reason: 'the one-second snapshot poll must be gone');
      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.pendingLookupId, isNull);
      expect(provider.isLoading, isFalse);
      expect(slept, isEmpty, reason: 'a settled answer needs no backoff');
    });

    test('reconnects with the cursor from the previous answer', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'running')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'running'),
          Lookup(id: 'lookup-1', status: 'done', result: pollSchedule()),
        ]
        ..cursors = ['cur-1', 'cur-2'];
      final provider = buildProvider(api);

      await select(provider);

      expect(api.afterCalls, [null, 'cur-1']);
      expect(api.waitCallCount, 2);
    });

    test('waits out the Retry-After the server asks for', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'running')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'running'),
          Lookup(id: 'lookup-1', status: 'done', result: pollSchedule()),
        ]
        ..retryAfters = [const Duration(seconds: 30)];
      final provider = buildProvider(api);

      await select(provider);

      expect(slept, [const Duration(seconds: 30)]);
    });

    test('falls back to its own backoff when no wait is asked for', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'running')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'running'),
          Lookup(id: 'lookup-1', status: 'done', result: pollSchedule()),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(slept, [LookupProvider.defaultReconnectDelay]);
    });

    test('stops at the two-minute cap and keeps the partial result', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        // The last answer repeats: this lookup never settles.
        ..waitResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'running',
            result: pollSchedule(),
          ),
        ]
        ..retryAfters = [const Duration(seconds: 30)];
      final provider = buildProvider(api);

      await select(provider);

      final total = slept.fold(Duration.zero, (a, b) => a + b);
      expect(total, lessThanOrEqualTo(const Duration(minutes: 2)));
      expect(slept, isNotEmpty);
      expect(api.createLookupCalls, 1,
          reason: 'a slow lookup is never resubmitted');
      expect(provider.pendingLookupId, 'lookup-1',
          reason: 'the id is kept for a later check');
      expect(provider.schedule?.collections.single.name, 'Black bin',
          reason: 'the partial result stays on screen');
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('resumes a retained lookup without submitting a new one', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'partial',
            result: pollSchedule(),
          ),
        ];
      final provider = buildProvider(api);

      await select(provider);
      expect(provider.pendingLookupId, 'lookup-1');

      // The next check finds the lookup finished.
      api.waitResponses = [
        Lookup(
          id: 'lookup-1',
          status: 'done',
          result: const Schedule(
            propertyId: 'p:4c5ee6c2f2c7c959',
            addressMatch: 'exact',
            collections: [
              Collection(
                name: 'Black bin',
                wasteType: 'refuse',
                dates: ['2026-09-10', '2026-09-24'],
              ),
            ],
          ),
        ),
      ];
      await provider.continuePendingLookup();

      expect(provider.pendingLookupId, isNull);
      expect(provider.schedule?.collections.single.dates,
          ['2026-09-10', '2026-09-24']);
      expect(api.createLookupCalls, 1,
          reason: 'resuming reconnects to the same lookup id');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('does nothing when there is no lookup to resume', () async {
      final api = FakeWhenIsBinsApi();
      final provider = buildProvider(api);

      await provider.continuePendingLookup();

      expect(api.waitCallCount, 0);
      expect(provider.isLoading, isFalse);
    });

    test('surfaces an ApiException raised by the wait endpoint', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'running')]
        ..error = const ApiException(
          statusCode: 429,
          problem: 'rate_limited',
          detail: 'Slow down.',
        );
      final provider = buildProvider(api);

      await select(provider);

      expect(provider.error?.problem, 'rate_limited');
      expect(provider.pendingLookupId, isNull);
      expect(provider.isLoading, isFalse);
    });
  });

  group('LookupProvider.restoreSchedule', () {
    Schedule savedSchedule() {
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
        byDate: [
          ByDateEntry(
            date: '2026-09-10',
            weekday: 'Thursday',
            collections: [
              ByDateCollection(name: 'Black bin', wasteType: 'refuse'),
            ],
          ),
        ],
        calendarUrl: 'https://whenisbins.com/100023336956.ics',
      );
    }

    test('hydrates the schedule from persisted data and notifies', () {
      final provider = LookupProvider(api: FakeWhenIsBinsApi());
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.restoreSchedule(savedSchedule());

      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.schedule?.collections.single.name, 'Black bin');
      expect(provider.schedule?.byDate.single.date, '2026-09-10');
      expect(provider.schedule?.calendarUrl,
          'https://whenisbins.com/100023336956.ics');
      expect(notifications, 1);
    });

    test('does nothing when there is no persisted schedule', () {
      final provider = LookupProvider(api: FakeWhenIsBinsApi());
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.restoreSchedule(null);

      expect(provider.schedule, isNull);
      expect(notifications, 0);
    });

    test('clears a previous error', () async {
      final api = FakeWhenIsBinsApi()
        ..error = const ApiException(
          statusCode: 404,
          problem: 'postcode_outside_coverage',
          detail: 'Postcode is outside coverage.',
        );
      final provider = LookupProvider(api: api);
      await provider.lookupPostcode('ZZ99 9ZZ');
      expect(provider.error, isNotNull);

      provider.restoreSchedule(savedSchedule());

      expect(provider.error, isNull);
      expect(provider.schedule, isNotNull);
    });
  });
}

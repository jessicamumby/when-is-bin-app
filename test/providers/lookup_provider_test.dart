import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('surfaces an ApiException raised by createLookup', () async {
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
      expect(provider.pendingLookupId, isNull,
          reason: 'no lookup was ever created, so there is none to keep');
      expect(provider.isLoading, isFalse);
    });

    test('pauses for the Retry-After on a mid-poll 429 and reconnects',
        () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        // The second answer repeats: the third wait reconnects and is done.
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'running'),
          Lookup(id: 'lookup-1', status: 'done', result: pollSchedule()),
        ]
        ..cursors = ['cur-1']
        // Many phones share one IPv4 address on a mobile network, so the
        // user's fifth open wait can be rate limited through no fault of
        // their own: the first wait answers, the second is throttled.
        ..waitErrors = [
          null,
          const ApiException(
            statusCode: 429,
            problem: 'rate_limited',
            detail: 'Slow down.',
            retryAfter: Duration(seconds: 2),
          ),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(provider.error, isNull,
          reason: 'a rate limit is the server problem, not the user one');
      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.pendingLookupId, isNull);
      expect(api.waitCallCount, 3, reason: 'the wait is retried, not abandoned');
      expect(api.afterCalls, [null, 'cur-1', 'cur-1'],
          reason: 'the retry follows the same cursor as the failed wait');
      expect(api.createLookupCalls, 1,
          reason: 'a rate limit must never resubmit the lookup');
      expect(slept, [
        LookupProvider.defaultReconnectDelay,
        const Duration(seconds: 2),
      ], reason: 'the ordinary backoff, then the wait the server asked for');
      expect(provider.isLoading, isFalse);
    });

    test('a 429 without a Retry-After still surfaces as an error', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'running')]
        ..waitErrors = [
          const ApiException(
            statusCode: 429,
            problem: 'rate_limited',
            detail: 'Slow down.',
          ),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(provider.error?.problem, 'rate_limited',
          reason: 'with no wait to honour there is nothing to retry with');
      expect(slept, isEmpty);
    });

    test('never sleeps past the wait budget for a long Retry-After', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitErrors = [
          const ApiException(
            statusCode: 429,
            problem: 'rate_limited',
            detail: 'Slow down.',
            retryAfter: Duration(minutes: 5),
          ),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(slept, [const Duration(minutes: 2)]);
      expect(api.waitCallCount, 1,
          reason: 'there was no budget left for another request');
      expect(provider.error, isNull);
      expect(provider.pendingLookupId, 'lookup-1',
          reason: 'the lookup is still running and kept for a later check');
    });

    test('keeps the pending lookup id when the wait itself fails', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitErrors = [
          const ApiException(
            statusCode: 0,
            problem: 'timeout',
            detail: 'The server took too long to respond. Please try again.',
          ),
        ];
      final provider = buildProvider(api);

      await select(provider);

      expect(provider.error?.problem, 'timeout');
      expect(provider.pendingLookupId, 'lookup-1',
          reason: 'the lookup was created: a later check must not resubmit it');
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

  group('LookupProvider.submitLookup', () {
    Schedule submittedSchedule() {
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

    test('sends the postcode plus the address fields the user gave', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done')];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(
        postcode: 'EH14 7AL',
        address: const {'street': 'A70--Glenbrook Rd To B7031'},
      );

      expect(api.lastLookupBody, {
        'postcode': 'EH14 7AL',
        'street': 'A70--Glenbrook Rd To B7031',
      });
    });

    test('a postcode-only journey sends no address fields', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done')];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(postcode: 'CB4 2HX', address: const {});

      expect(api.lastLookupBody, {'postcode': 'CB4 2HX'});
    });

    test('waits for the lookup and applies the schedule', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'done', result: submittedSchedule()),
        ];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(
        postcode: 'EH14 7AL',
        address: const {'property': '15 Example Court'},
      );

      expect(api.createLookupCalls, 1);
      expect(api.waitCallCount, 1,
          reason: 'the general path reuses the /wait long-poll');
      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('sends a valid idempotency key (visible ASCII, no spaces)', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'done')];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(
        postcode: 'CB4 2HX',
        address: const {'property': '15 Example Court'},
      );

      final key = api.lastIdempotencyKey!;
      expect(key.length, inInclusiveRange(1, 128));
      expect(key, isNot(contains(RegExp(r'\s'))),
          reason: 'Idempotency-Key must not contain whitespace');
      expect(RegExp(r'^[\x21-\x7E]+$').hasMatch(key), isTrue,
          reason: 'Idempotency-Key must be visible ASCII only');
    });

    test('surfaces a failed lookup and clears the schedule', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          Lookup(
            id: 'lookup-1',
            status: 'failed',
            detail: "The council's system doesn't list that road.",
          ),
        ];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(
        postcode: 'EH14 7AL',
        address: const {'street': 'Nowhere Road'},
      );

      expect(provider.schedule, isNull);
      expect(provider.error?.detail,
          "The council's system doesn't list that road.");
      expect(provider.pendingLookupId, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('selectAddress submits the candidate through the same path', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [Lookup(id: 'lookup-1', status: 'queued')]
        ..waitResponses = [
          Lookup(id: 'lookup-1', status: 'done', result: submittedSchedule()),
        ];
      final provider = LookupProvider(api: api);

      await provider.selectAddress(_candidate, postcode: 'CB4 2HX');

      expect(api.lastLookupBody, {
        'postcode': 'CB4 2HX',
        'property_id': 'p:4c5ee6c2f2c7c959',
      });
      expect(api.waitCallCount, 1);
      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
    });
  });

  group('LookupProvider.refineAddressLookup', () {
    AddressLookup streetLookup({List<InputOption> options = const []}) {
      return AddressLookup(
        postcode: 'EH14 7AL',
        requiredInput: 'street',
        inputOptions: InputOptions(
          field: 'street',
          needsMoreQuery: true,
          notListedValue: '__not_listed__',
          options: options,
        ),
      );
    }

    test('re-asks /addresses with the narrower q and keeps the answer',
        () async {
      final api = FakeWhenIsBinsApi()
        ..addressLookupResponses = [
          streetLookup(),
          streetLookup(
            options: const [
              InputOption(
                value: 'A70--Glenbrook Rd To B7031',
                label: 'A70--Glenbrook Rd To B7031',
              ),
            ],
          ),
        ];
      final provider = LookupProvider(api: api);
      await provider.lookupPostcode('EH14 7AL');

      await provider.refineAddressLookup('A70');

      expect(api.lastPostcode, 'EH14 7AL',
          reason: 'the postcode is still the one being resolved');
      expect(api.lastAddressQuery, 'A70');
      expect(provider.addressLookup?.inputOptions?.options, hasLength(1));
      expect(provider.addressLookup?.inputOptions?.options.first.label,
          'A70--Glenbrook Rd To B7031');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('surfaces a failed re-query but keeps the options on screen',
        () async {
      final api = FakeWhenIsBinsApi()
        ..addressLookupResponses = [streetLookup()];
      final provider = LookupProvider(api: api);
      await provider.lookupPostcode('EH14 7AL');

      api.error = const ApiException(
        statusCode: 429,
        problem: 'rate_limited',
        detail: 'Slow down.',
      );
      await provider.refineAddressLookup('A70');

      expect(provider.error?.problem, 'rate_limited');
      expect(provider.addressLookup, isNotNull,
          reason: 'losing the list would strand the user mid-form');
      expect(provider.isLoading, isFalse);
    });

    test('does nothing before a postcode is known', () async {
      final api = FakeWhenIsBinsApi();
      final provider = LookupProvider(api: api);

      await provider.refineAddressLookup('A70');

      expect(api.addressQueries, isEmpty);
      expect(provider.isLoading, isFalse);
    });
  });


  group('LookupProvider.failedLookup', () {
    /// A council that offered to answer for a neighbouring property.
    const failedLookup = Lookup(
      id: 'lookup-1',
      status: 'failed',
      problem: 'address_not_found',
      detail: 'No exact address match.',
      council: Council(
        id: 'cambridge',
        name: 'Cambridge City Council',
        lookupUrl: 'https://www.cambridge.gov.uk/bins',
      ),
      candidates: [AddressCandidate(id: 'p:1', label: '15 Example Court')],
    );

    test('exposes the failed lookup with its problem, candidates and link',
        () async {
      final api = FakeWhenIsBinsApi()..lookupResponses = [failedLookup];
      final provider = LookupProvider(api: api);

      await provider.submitLookup(
        postcode: 'CB4 2HX',
        address: const {'property': '15 Example Court'},
      );

      expect(provider.failedLookup, isNotNull,
          reason: 'the UI needs the council link and the alternatives');
      expect(provider.failedLookup?.problem, 'address_not_found',
          reason: 'the real reason must survive, not just lookup_failed');
      expect(provider.failedLookup?.candidates.single.id, 'p:1');
      expect(provider.failedLookup?.candidates.single.label,
          '15 Example Court');
      expect(provider.failedLookup?.council?.lookupUrl,
          'https://www.cambridge.gov.uk/bins');
      expect(provider.failedLookup?.detail, 'No exact address match.');
      expect(provider.error?.problem, 'lookup_failed',
          reason: 'the summary the UI already reads is unchanged');
      expect(provider.schedule, isNull);
    });

    test('clears the failed lookup when a later lookup settles', () async {
      final api = FakeWhenIsBinsApi()..lookupResponses = [failedLookup];
      final provider = LookupProvider(api: api);
      await provider.submitLookup(
        postcode: 'CB4 2HX',
        address: const {'property': '15 Example Court'},
      );
      expect(provider.failedLookup, isNotNull);

      api.lookupResponses = [
        Lookup(
          id: 'lookup-2',
          status: 'done',
          result: Schedule(
            propertyId: 'p:4c5ee6c2f2c7c959',
            addressMatch: 'postcode_representative',
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

      await provider.submitLookup(
        postcode: 'CB4 2HX',
        address: const {'property': '15 Example Court'},
      );

      expect(provider.failedLookup, isNull,
          reason: 'a stale failure must not shadow a fresh schedule');
      expect(provider.schedule?.addressMatch, 'postcode_representative');
    });
  });

  group('LookupProvider.submitWithPostcodeRepresentative', () {
    Schedule neighbourSchedule() {
      return const Schedule(
        propertyId: 'p:4c5ee6c2f2c7c959',
        addressMatch: 'postcode_representative',
        collections: [
          Collection(
            name: 'Black bin',
            wasteType: 'refuse',
            dates: ['2026-09-10'],
          ),
        ],
      );
    }

    test('resubmits the same address with consent and a fresh key', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          const Lookup(
            id: 'lookup-1',
            status: 'failed',
            problem: 'address_not_found',
            detail: 'No exact address match.',
          ),
        ];
      final provider = LookupProvider(api: api);
      await provider.submitLookup(
        postcode: 'EH14 7AL',
        address: const {'street': 'A70--Glenbrook Rd To B7031'},
      );
      final firstKey = api.lastIdempotencyKey;

      api.lookupResponses = [
        Lookup(id: 'lookup-2', status: 'done', result: neighbourSchedule()),
      ];
      await provider.submitWithPostcodeRepresentative(postcode: 'EH14 7AL');

      expect(api.lastLookupBody, {
        'postcode': 'EH14 7AL',
        'street': 'A70--Glenbrook Rd To B7031',
        'allow_postcode_representative': true,
      }, reason: 'the same address, plus the consent the user gave');
      expect(api.createLookupCalls, 2);
      expect(api.lastIdempotencyKey, isNot(firstKey),
          reason: 'a resubmit is new work, so it needs its own key');
      expect(provider.schedule?.addressMatch, 'postcode_representative');
      expect(provider.error, isNull);
      expect(provider.failedLookup, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('does nothing when no address has been submitted', () async {
      final api = FakeWhenIsBinsApi();
      final provider = LookupProvider(api: api);

      await provider.submitWithPostcodeRepresentative(postcode: 'EH14 7AL');

      expect(api.createLookupCalls, 0);
      expect(api.waitCallCount, 0);
      expect(provider.isLoading, isFalse);
    });
  });

  group('LookupProvider.activeLookup', () {
    late DateTime now;

    LookupProvider buildProvider(FakeWhenIsBinsApi api) {
      now = DateTime(2026, 9, 23, 12);
      return LookupProvider(
        api: api,
        delay: (duration) async => now = now.add(duration),
        now: () => now,
      );
    }

    Schedule settledSchedule() {
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

    test('has nothing in flight before anything is submitted', () {
      final provider = buildProvider(FakeWhenIsBinsApi());

      expect(provider.activeLookup, isNull);
    });

    test('exposes the in-flight lookup as the poll advances', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          const Lookup(
            id: 'lookup-1',
            status: 'queued',
            expectedWaitSeconds: 60,
          ),
        ]
        ..waitResponses = [
          const Lookup(
            id: 'lookup-1',
            status: 'running',
            expectedWaitSeconds: 45,
            queueAhead: 3,
            progress: LookupProgress(
              stage: 'council',
              message: 'Asking your council for your dates',
            ),
          ),
          Lookup(id: 'lookup-1', status: 'done', result: settledSchedule()),
        ];
      final provider = buildProvider(api);
      final seen = <int?>[];
      provider.addListener(
        () => seen.add(provider.activeLookup?.expectedWaitSeconds),
      );

      await provider.selectAddress(_candidate, postcode: 'CB4 2HX');

      expect(seen, contains(60),
          reason: 'the lookup as created is what the wait starts from');
      expect(seen, contains(45),
          reason: 'each answer from /wait updates the figure on screen');
      expect(provider.activeLookup, isNull,
          reason: 'nothing is in flight once the lookup settles');
      expect(provider.schedule?.propertyId, 'p:4c5ee6c2f2c7c959');
    });

    test('clears the in-flight lookup when it fails', () async {
      final api = FakeWhenIsBinsApi()
        ..lookupResponses = [
          const Lookup(
            id: 'lookup-1',
            status: 'failed',
            problem: 'address_not_found',
            detail: 'No exact address match.',
          ),
        ];
      final provider = buildProvider(api);

      await provider.selectAddress(_candidate, postcode: 'CB4 2HX');

      expect(provider.failedLookup, isNotNull);
      expect(provider.activeLookup, isNull);
    });
  });

  group('LookupProvider with a failing transport', () {
    // The real client, so the provider sees exactly what the API raises.
    LookupProvider providerFailingWith(Object failure) {
      final api = WhenIsBinsApi(
        client: MockClient((request) async => throw failure),
        baseUrl: 'https://whenisbins.com/v1',
      );
      return LookupProvider(api: api);
    }

    test('a failed TLS handshake on lookupPostcode becomes an error, not a '
        'crash', () async {
      final provider = providerFailingWith(
        const HandshakeException('Handshake error in client'),
      );

      await provider.lookupPostcode('CB4 2HX');

      expect(provider.error?.problem, WhenIsBinsApi.networkProblem);
      expect(provider.isLoading, isFalse);
    });

    test('a dropped connection on a submitted lookup becomes an error, not a '
        'crash', () async {
      final provider = providerFailingWith(
        const SocketException('Connection reset by peer'),
      );

      await provider.selectAddress(_candidate, postcode: 'CB4 2HX');

      expect(provider.error?.problem, WhenIsBinsApi.networkProblem);
      expect(provider.schedule, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('JSON of the wrong shape becomes an error, not a crash', () async {
      final api = WhenIsBinsApi(
        client: MockClient(
          (request) async => http.Response('{"postcode": 42}', 200),
        ),
        baseUrl: 'https://whenisbins.com/v1',
      );
      final provider = LookupProvider(api: api);

      await provider.lookupPostcode('CB4 2HX');

      expect(provider.error?.problem, WhenIsBinsApi.invalidResponseProblem);
      expect(provider.addressLookup, isNull);
    });
  });
}

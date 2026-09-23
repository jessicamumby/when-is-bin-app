import 'package:flutter_test/flutter_test.dart';
import 'package:when_is_bin_app/models/schedule.dart';

void main() {
  group('Collection.fromJson', () {
    test('parses a collection with dates and bin colours', () {
      final json = {
        'name': 'Black bin',
        'waste_type': 'refuse',
        'dates': ['2026-09-10', '2026-09-24'],
        'dates_complete': true,
        'bin_colour': 'black',
        'lid_colour': 'black',
        'colour_source': 'council',
        'container': 'wheelie_bin',
      };

      final collection = Collection.fromJson(json);

      expect(collection.name, 'Black bin');
      expect(collection.wasteType, 'refuse');
      expect(collection.dates, ['2026-09-10', '2026-09-24']);
      expect(collection.datesComplete, isTrue);
      expect(collection.binColour, 'black');
      expect(collection.lidColour, 'black');
      expect(collection.colourSource, 'council');
      expect(collection.container, 'wheelie_bin');
    });

    test('defaults missing optional fields', () {
      final json = {
        'name': 'Garden waste',
        'waste_type': 'garden',
        'dates': ['2026-09-12'],
      };

      final collection = Collection.fromJson(json);

      expect(collection.datesComplete, isFalse);
      expect(collection.binColour, isNull);
      expect(collection.lidColour, isNull);
      expect(collection.colourSource, isNull);
      expect(collection.container, isNull);
      expect(collection.subscriptionRequired, isFalse);
    });
  });

  group('Schedule.fromJson', () {
    test('parses a full schedule with collections and by_date', () {
      final json = {
        'property_id': 'p:4c5ee6c2f2c7c959',
        'address_match': 'exact',
        'council': {
          'id': 'E07000008',
          'name': 'Cambridge City Council',
        },
        'collections': [
          {
            'name': 'Black bin',
            'waste_type': 'refuse',
            'dates': ['2026-09-10'],
          },
        ],
        'by_date': [
          {
            'date': '2026-09-10',
            'weekday': 'Thursday',
            'collections': [
              {'name': 'Black bin', 'waste_type': 'refuse'},
            ],
          },
        ],
        'date_confidence': 'published_calendar',
        'date_completeness': 'limited_horizon',
        'evidence_granularity': 'property',
        'retrieved_at': '2026-09-07T09:00:01Z',
        'source_url': 'https://www.cambridge.gov.uk/check-when-your-bin-will-be-emptied',
        'calendar_url': 'https://whenisbins.com/100023336956.ics',
        'uprn': '100023336956',
      };

      final schedule = Schedule.fromJson(json);

      expect(schedule.propertyId, 'p:4c5ee6c2f2c7c959');
      expect(schedule.addressMatch, 'exact');
      expect(schedule.council?.name, 'Cambridge City Council');
      expect(schedule.collections, hasLength(1));
      expect(schedule.byDate, hasLength(1));
      expect(schedule.byDate.first.date, '2026-09-10');
      expect(schedule.byDate.first.weekday, 'Thursday');
      expect(schedule.dateConfidence, 'published_calendar');
      expect(schedule.dateCompleteness, 'limited_horizon');
      expect(schedule.evidenceGranularity, 'property');
      expect(schedule.retrievedAt, '2026-09-07T09:00:01Z');
      expect(schedule.sourceUrl,
          'https://www.cambridge.gov.uk/check-when-your-bin-will-be-emptied');
      expect(schedule.calendarUrl, 'https://whenisbins.com/100023336956.ics');
      expect(schedule.uprn, '100023336956');
    });

    test('handles a schedule with no by_date', () {
      final json = {
        'property_id': 'p:abc',
        'address_match': 'exact',
        'collections': [
          {
            'name': 'Blue bin',
            'waste_type': 'recycling',
            'dates': ['2026-09-17'],
          },
        ],
      };

      final schedule = Schedule.fromJson(json);

      expect(schedule.byDate, isEmpty);
      expect(schedule.council, isNull);
      expect(schedule.calendarUrl, isNull);
    });
  });

  group('Collection.toJson', () {
    test('writes every field with the API snake_case keys', () {
      const collection = Collection(
        name: 'Black bin',
        wasteType: 'refuse',
        dates: ['2026-09-10', '2026-09-24'],
        datesComplete: true,
        binColour: 'black',
        lidColour: 'grey',
        colourSource: 'council',
        container: 'wheelie_bin',
        subscriptionRequired: true,
      );

      final json = collection.toJson();

      expect(json['name'], 'Black bin');
      expect(json['waste_type'], 'refuse');
      expect(json['dates'], ['2026-09-10', '2026-09-24']);
      expect(json['dates_complete'], isTrue);
      expect(json['bin_colour'], 'black');
      expect(json['lid_colour'], 'grey');
      expect(json['colour_source'], 'council');
      expect(json['container'], 'wheelie_bin');
      expect(json['subscription_required'], isTrue);
    });

    test('round-trips through fromJson without losing data', () {
      const collection = Collection(
        name: 'Garden waste',
        wasteType: 'garden',
        dates: ['2026-09-12'],
      );

      final restored = Collection.fromJson(collection.toJson());

      expect(restored.name, 'Garden waste');
      expect(restored.wasteType, 'garden');
      expect(restored.dates, ['2026-09-12']);
      expect(restored.datesComplete, isFalse);
      expect(restored.subscriptionRequired, isFalse);
    });
  });

  group('ByDateEntry.toJson', () {
    test('round-trips the date, weekday and collections', () {
      const entry = ByDateEntry(
        date: '2026-09-10',
        weekday: 'Thursday',
        collections: [
          ByDateCollection(
            name: 'Black bin',
            wasteType: 'refuse',
            subscriptionRequired: true,
          ),
        ],
      );

      final json = entry.toJson();

      expect(json['date'], '2026-09-10');
      expect(json['weekday'], 'Thursday');
      final collections = json['collections'] as List<dynamic>;
      expect(collections, hasLength(1));
      expect((collections.first as Map<String, dynamic>)['name'], 'Black bin');
      expect(
        (collections.first as Map<String, dynamic>)['waste_type'],
        'refuse',
      );

      final restored = ByDateEntry.fromJson(json);
      expect(restored.date, '2026-09-10');
      expect(restored.weekday, 'Thursday');
      expect(restored.collections.single.name, 'Black bin');
      expect(restored.collections.single.wasteType, 'refuse');
      expect(restored.collections.single.subscriptionRequired, isTrue);
    });
  });
}

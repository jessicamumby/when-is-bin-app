import 'address_lookup.dart';

/// One council waste service (e.g. "Black bin", "Recycling").
class Collection {
  const Collection({
    required this.name,
    required this.wasteType,
    required this.dates,
    this.datesComplete = false,
    this.binColour,
    this.lidColour,
    this.colourSource,
    this.container,
    this.subscriptionRequired = false,
  });

  final String name;
  final String wasteType;
  final List<String> dates;
  final bool datesComplete;
  final String? binColour;
  final String? lidColour;
  final String? colourSource;
  final String? container;
  final bool subscriptionRequired;

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      name: json['name'] as String,
      wasteType: json['waste_type'] as String,
      dates: (json['dates'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      datesComplete: json['dates_complete'] as bool? ?? false,
      binColour: json['bin_colour'] as String?,
      lidColour: json['lid_colour'] as String?,
      colourSource: json['colour_source'] as String?,
      container: json['container'] as String?,
      subscriptionRequired: json['subscription_required'] as bool? ?? false,
    );
  }
}

/// The services due on a single collection date.
class ByDateEntry {
  const ByDateEntry({
    required this.date,
    required this.weekday,
    required this.collections,
  });

  final String date;
  final String weekday;
  final List<ByDateCollection> collections;

  factory ByDateEntry.fromJson(Map<String, dynamic> json) {
    return ByDateEntry(
      date: json['date'] as String,
      weekday: json['weekday'] as String,
      collections: (json['collections'] as List<dynamic>? ?? const [])
          .map((e) => ByDateCollection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ByDateCollection {
  const ByDateCollection({
    required this.name,
    required this.wasteType,
    this.subscriptionRequired = false,
  });

  final String name;
  final String wasteType;
  final bool subscriptionRequired;

  factory ByDateCollection.fromJson(Map<String, dynamic> json) {
    return ByDateCollection(
      name: json['name'] as String,
      wasteType: json['waste_type'] as String,
      subscriptionRequired: json['subscription_required'] as bool? ?? false,
    );
  }
}

/// A stable, address-free collection schedule for a property.
class Schedule {
  const Schedule({
    required this.propertyId,
    required this.addressMatch,
    this.council,
    this.collections = const [],
    this.byDate = const [],
    this.dateConfidence,
    this.dateCompleteness,
    this.evidenceGranularity,
    this.retrievedAt,
    this.sourceUrl,
    this.calendarUrl,
    this.uprn,
    this.provisional = false,
  });

  final String propertyId;
  final String addressMatch;
  final Council? council;
  final List<Collection> collections;
  final List<ByDateEntry> byDate;
  final String? dateConfidence;
  final String? dateCompleteness;
  final String? evidenceGranularity;
  final String? retrievedAt;
  final String? sourceUrl;
  final String? calendarUrl;
  final String? uprn;
  final bool provisional;

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      propertyId: json['property_id'] as String,
      addressMatch: json['address_match'] as String,
      council: json['council'] == null
          ? null
          : Council.fromJson(json['council'] as Map<String, dynamic>),
      collections: (json['collections'] as List<dynamic>? ?? const [])
          .map((e) => Collection.fromJson(e as Map<String, dynamic>))
          .toList(),
      byDate: (json['by_date'] as List<dynamic>? ?? const [])
          .map((e) => ByDateEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      dateConfidence: json['date_confidence'] as String?,
      dateCompleteness: json['date_completeness'] as String?,
      evidenceGranularity: json['evidence_granularity'] as String?,
      retrievedAt: json['retrieved_at'] as String?,
      sourceUrl: json['source_url'] as String?,
      calendarUrl: json['calendar_url'] as String?,
      uprn: json['uprn'] as String?,
      provisional: json['provisional'] as bool? ?? false,
    );
  }
}

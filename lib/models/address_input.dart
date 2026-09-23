/// The extra inputs a council can ask for beyond the postcode.
///
/// This is the app's view of the API's `required_input` matrix: each value
/// maps to the fields that have to be sent to `POST /lookups`.
enum AddressField {
  /// The first line of the address (`property`).
  property,

  /// A road/street name (`street`).
  street,

  /// A settlement, area or council-recognised road (`locality`).
  locality,

  /// The day the bins are normally collected (`normal_weekday`).
  weekday,

  /// What kind of property it is (`property_type`).
  propertyType,
}

/// The fields a council's `required_input` asks the user for.
class AddressInputSpec {
  const AddressInputSpec(this.fields);

  /// The fields to collect, in the order the API guide lists them.
  final List<AddressField> fields;

  /// A council that needs nothing beyond the postcode.
  static const none = AddressInputSpec([]);

  /// The fields to collect for a `required_input` value.
  ///
  /// An unrecognised value — a new one the API has added, or `property_id`
  /// where the candidate list is empty — asks for nothing extra, which is the
  /// same body shape as `none`: postcode only. That is a body the council can
  /// still answer, rather than a dead end.
  static AddressInputSpec forRequiredInput(String requiredInput) {
    switch (requiredInput) {
      case 'property':
        return const AddressInputSpec([AddressField.property]);
      case 'street':
        return const AddressInputSpec([AddressField.street]);
      case 'road_and_locality':
        return const AddressInputSpec([
          AddressField.street,
          AddressField.locality,
        ]);
      case 'street_and_property':
        return const AddressInputSpec([
          AddressField.street,
          AddressField.property,
        ]);
      case 'settlement':
      case 'settlement_or_road':
        return const AddressInputSpec([AddressField.locality]);
      case 'normal_weekday':
        return const AddressInputSpec([AddressField.weekday]);
      case 'normal_weekday_and_locality':
        return const AddressInputSpec([
          AddressField.weekday,
          AddressField.locality,
        ]);
      case 'property_type':
        return const AddressInputSpec([AddressField.propertyType]);
      default:
        return none;
    }
  }

  bool get isEmpty => fields.isEmpty;

  bool includes(AddressField field) => fields.contains(field);
}

/// The `property_type` values the API currently accepts, and how to label them.
class PropertyTypes {
  const PropertyTypes._();

  static const _labels = <String, String>{
    'private_flat_without_bin_store': 'A private flat with no bin store',
    'private_block_with_bin_store': 'A private block with a bin store',
    'housing_estate': 'A housing estate',
    'street_bag_collection': 'Bags collected from the street',
  };

  /// The values a `property_type` journey may send, in picker order.
  static List<String> get values => _labels.keys.toList();

  /// A human-readable label for a `property_type` value.
  static String labelFor(String value) => _labels[value] ?? value;
}

/// The weekdays a `normal_weekday` journey may send, in week order.
const weekdayNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Build the address part of a `POST /lookups` body.
///
/// Only the fields the [spec] asks for are included — sending a field the
/// council did not request is not the answer it is waiting for — and blank
/// values are dropped rather than sent empty, so a blank reads as a missing
/// answer instead of a wrong one.
Map<String, dynamic> buildAddressBody({
  required AddressInputSpec spec,
  String? property,
  String? street,
  String? locality,
  String? weekday,
  String? propertyType,
}) {
  final body = <String, dynamic>{};
  void add(AddressField field, String? key, String? value) {
    if (!spec.includes(field)) return;
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    body[key!] = trimmed;
  }

  add(AddressField.property, 'property', property);
  add(AddressField.street, 'street', street);
  add(AddressField.locality, 'locality', locality);
  add(AddressField.weekday, 'normal_weekday', weekday);
  add(AddressField.propertyType, 'property_type', propertyType);
  return body;
}

/// The value to send for a field that is backed by the council's option list.
///
/// [selected] is the option the user tapped, [typed] is what they typed in the
/// fallback box, and [notListedValue] is the API's own "none of these"
/// sentinel. Picking the sentinel means "my road is not in this list", so what
/// gets sent is the typed text — the sentinel itself must never reach a
/// council, because it is not an address. The result is null while the user
/// has not actually answered, which the screen turns into a validation error.
String? resolvedChoice({String? selected, String? typed, String? notListedValue}) {
  final chosen = selected?.trim();
  if (chosen != null && chosen.isNotEmpty && chosen != notListedValue) {
    return chosen;
  }
  final text = typed?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

/// A human-readable label for an address the user described by hand, for the
/// saved-address shortcut. Falls back to the postcode when the journey asked
/// for nothing that reads as an address (a weekday, a property type).
String describeAddress({
  required String postcode,
  String? property,
  String? street,
  String? locality,
}) {
  final parts = [property, street, locality]
      .map((part) => part?.trim())
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return postcode;
  return '${parts.join(', ')}, $postcode';
}

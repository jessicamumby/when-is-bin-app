/// UK postcode shape rules, shared by every screen that takes a postcode.
///
/// The check is deliberately generous: it accepts the formatting variations a
/// person actually types (upper or lower case, with or without the usual
/// space), but rejects anything that is not a postcode shape at all, so an
/// obviously wrong value never costs a network round trip.
class UkPostcode {
  UkPostcode._();

  /// An outward code (`[A-Z]{1,2}` area + `[0-9][0-9A-Z]?` district), an
  /// optional space, then the inward code (`[0-9][A-Z]{2}`).
  ///
  /// `GIR 0AA` is the single UK postcode that is not an area/district pair, so
  /// it is spelled out rather than loosening the pattern for every other
  /// postcode.
  static final RegExp _shape = RegExp(
    r'^(?:GIR ?0AA|[A-Z]{1,2}[0-9][0-9A-Z]? ?[0-9][A-Z]{2})$',
  );

  /// The shortest and longest a space-free UK postcode can be (`M11AE` …
  /// `SW1A1AA`).
  static const int _minLength = 5;
  static const int _maxLength = 7;

  /// Uppercase and trim [input], collapsing any run of whitespace inside it to
  /// a single space. `' cb4   2hx '` becomes `'CB4 2HX'`.
  static String normalise(String input) {
    return input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Whether [input] is a UK postcode in any of its normal written forms.
  static bool isValid(String input) {
    final normalised = normalise(input);
    final compact = normalised.replaceAll(' ', '');
    if (compact.length < _minLength || compact.length > _maxLength) return false;
    return _shape.hasMatch(normalised);
  }
}

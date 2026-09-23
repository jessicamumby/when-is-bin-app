/// A council-provided property candidate the user can select.
class AddressCandidate {
  const AddressCandidate({required this.id, required this.label});

  final String id;
  final String label;

  factory AddressCandidate.fromJson(Map<String, dynamic> json) {
    return AddressCandidate(
      id: json['id'] as String,
      label: json['label'] as String,
    );
  }
}

/// A road/area option for councils that collect by road or area.
class InputOption {
  const InputOption({required this.value, required this.label});

  final String value;
  final String label;

  factory InputOption.fromJson(Map<String, dynamic> json) {
    return InputOption(
      value: json['value'] as String,
      label: json['label'] as String,
    );
  }
}

/// Council-provided roads or areas used to narrow a street-based lookup.
class InputOptions {
  const InputOptions({
    required this.field,
    required this.needsMoreQuery,
    this.notListedValue,
    this.options = const [],
  });

  final String field;
  final bool needsMoreQuery;
  final String? notListedValue;
  final List<InputOption> options;

  factory InputOptions.fromJson(Map<String, dynamic> json) {
    return InputOptions(
      field: json['field'] as String,
      needsMoreQuery: json['needs_more_query'] as bool? ?? false,
      notListedValue: json['not_listed_value'] as String?,
      options: (json['options'] as List<dynamic>? ?? const [])
          .map((e) => InputOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The collecting council for a postcode.
class Council {
  const Council({
    required this.id,
    required this.name,
    this.lookupUrl,
    this.expectedWaitSeconds,
    this.successRate,
  });

  final String id;
  final String name;
  final String? lookupUrl;
  final int? expectedWaitSeconds;
  final double? successRate;

  factory Council.fromJson(Map<String, dynamic> json) {
    return Council(
      id: json['id'] as String,
      name: json['name'] as String,
      lookupUrl: json['lookup_url'] as String?,
      expectedWaitSeconds: json['expected_wait_seconds'] as int?,
      successRate: (json['success_rate'] as num?)?.toDouble(),
    );
  }
}

/// The response from `GET /addresses`: the council and what input it needs.
class AddressLookup {
  const AddressLookup({
    required this.postcode,
    required this.requiredInput,
    this.council,
    this.postcodeRepresentative,
    this.candidatesSource,
    this.candidates = const [],
    this.inputOptions,
  });

  final String postcode;
  final String requiredInput;
  final Council? council;
  final String? postcodeRepresentative;
  final String? candidatesSource;
  final List<AddressCandidate> candidates;
  final InputOptions? inputOptions;

  factory AddressLookup.fromJson(Map<String, dynamic> json) {
    return AddressLookup(
      postcode: json['postcode'] as String,
      requiredInput: json['required_input'] as String,
      council: json['council'] == null
          ? null
          : Council.fromJson(json['council'] as Map<String, dynamic>),
      postcodeRepresentative: json['postcode_representative'] as String?,
      candidatesSource: json['candidates_source'] as String?,
      candidates: (json['candidates'] as List<dynamic>? ?? const [])
          .map((e) => AddressCandidate.fromJson(e as Map<String, dynamic>))
          .toList(),
      inputOptions: json['input_options'] == null
          ? null
          : InputOptions.fromJson(json['input_options'] as Map<String, dynamic>),
    );
  }
}

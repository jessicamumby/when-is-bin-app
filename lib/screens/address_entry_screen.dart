import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_error_copy.dart';
import '../core/theme.dart';
import '../models/address_input.dart';
import '../models/address_lookup.dart';
import '../models/lookup.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import 'schedule_screen.dart';

/// Collects the extra input a council needs when a postcode alone does not
/// identify one property: a first line, a street, an area, a weekday or a
/// property type.
///
/// Which fields appear is driven entirely by the `/addresses` answer, so this
/// one screen covers every `required_input` journey that has no candidate list.
class AddressEntryScreen extends StatefulWidget {
  const AddressEntryScreen({super.key, required this.addressLookup});

  /// The `/addresses` answer this form was opened for. A newer answer from the
  /// provider wins, which is how a narrowed short list reaches the picker.
  final AddressLookup addressLookup;

  @override
  State<AddressEntryScreen> createState() => _AddressEntryScreenState();
}

class _AddressEntryScreenState extends State<AddressEntryScreen> {
  final _propertyController = TextEditingController();
  final _streetController = TextEditingController();
  final _localityController = TextEditingController();
  final _queryController = TextEditingController();

  String? _pickedStreet;
  String? _pickedLocality;
  bool _streetNotListed = false;
  bool _localityNotListed = false;
  String? _weekday;
  String? _propertyType;
  String? _validationError;

  @override
  void dispose() {
    _propertyController.dispose();
    _streetController.dispose();
    _localityController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LookupProvider>();
    final lookup = provider.addressLookup ?? widget.addressLookup;
    final spec = AddressInputSpec.forRequiredInput(lookup.requiredInput);

    return Scaffold(
      appBar: AppBar(title: const Text('Your address')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A few more details',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${lookup.council?.name ?? 'Your council'} \u2022 '
              '${lookup.postcode}',
              style: const TextStyle(fontSize: 16, color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            if (provider.isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              for (final field in spec.fields) ..._fieldsFor(field, lookup),
              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _validationError!,
                  style: const TextStyle(fontSize: 16, color: AppColors.error),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _submit(lookup, spec),
                  child: const Text('Find my bin day'),
                ),
              ),
              if (provider.error != null) ...[
                const SizedBox(height: 16),
                _LookupErrorCard(
                  detail: _errorDetail(provider),
                  retryCopy: apiRetryAfterCopy(provider.error!.retryAfter),
                  councilUrl: provider.failedLookup?.council?.lookupUrl,
                  candidates: _offeredAddresses(provider),
                  offerNeighbour:
                      _canOfferNeighbour(provider.failedLookup, lookup),
                  onOpenCouncil: _openCouncil,
                  onPickCandidate: (candidate) =>
                      _pickCandidate(candidate, lookup),
                  onUseNeighbour: () => _useNeighbour(lookup),
                  onStartOver: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The widgets for one field of the council's `required_input`.
  List<Widget> _fieldsFor(AddressField field, AddressLookup lookup) {
    switch (field) {
      case AddressField.property:
        return [
          TextField(
            controller: _propertyController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'First line of your address',
            ),
          ),
          const SizedBox(height: 16),
        ];
      case AddressField.street:
        return _pickerSection(
          title: 'Street',
          freeTextLabel: 'Street',
          icon: Icons.signpost_outlined,
          options: _optionsFor(AddressField.street, lookup),
          controller: _streetController,
          picked: _pickedStreet,
          notListed: _streetNotListed,
          onPicked: (value) => setState(() {
            _pickedStreet = value;
            _streetNotListed = false;
          }),
          onNotListed: (value) => setState(() => _streetNotListed = value),
        );
      case AddressField.locality:
        return _pickerSection(
          title: 'Area',
          freeTextLabel: 'Area',
          icon: Icons.place_outlined,
          hint: 'The village or area you live in.',
          options: _optionsFor(AddressField.locality, lookup),
          controller: _localityController,
          picked: _pickedLocality,
          notListed: _localityNotListed,
          onPicked: (value) => setState(() {
            _pickedLocality = value;
            _localityNotListed = false;
          }),
          onNotListed: (value) => setState(() => _localityNotListed = value),
        );
      case AddressField.weekday:
        return [
          const _FieldTitle('Which day are your bins usually collected?'),
          for (final day in weekdayNames)
            _ChoiceTile(
              label: day,
              icon: Icons.event_outlined,
              selected: _weekday == day,
              onTap: () => setState(() => _weekday = day),
            ),
          const SizedBox(height: 16),
        ];
      case AddressField.propertyType:
        return [
          const _FieldTitle('What kind of property is it?'),
          for (final value in PropertyTypes.values)
            _ChoiceTile(
              label: PropertyTypes.labelFor(value),
              icon: Icons.apartment_outlined,
              selected: _propertyType == value,
              onTap: () => setState(() => _propertyType = value),
            ),
          const SizedBox(height: 16),
        ];
    }
  }

  /// A field backed by the council's option list: the options to pick from, a
  /// search box when the council asked for a narrower query, and a way to say
  /// "none of these" — which falls back to typing, because the not-listed
  /// sentinel is not an address and is never submitted.
  List<Widget> _pickerSection({
    required String title,
    required String freeTextLabel,
    required IconData icon,
    required InputOptions? options,
    required TextEditingController controller,
    required String? picked,
    required bool notListed,
    required void Function(String?) onPicked,
    required void Function(bool) onNotListed,
    String? hint,
  }) {
    final widgets = <Widget>[_FieldTitle(title)];
    if (hint != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(hint, style: const TextStyle(color: AppColors.muted)),
        ),
      );
    }

    if (options == null || notListed) {
      widgets.add(
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: freeTextLabel),
        ),
      );
      if (options != null) {
        widgets.add(
          TextButton(
            onPressed: () => onNotListed(false),
            child: const Text('Show the list again'),
          ),
        );
      }
    } else {
      if (options.needsMoreQuery) {
        widgets.add(
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search for your street or area',
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _search, child: const Text('Search')),
            ],
          ),
        );
        widgets.add(const SizedBox(height: 8));
      }
      for (final option in options.options) {
        widgets.add(
          _ChoiceTile(
            label: option.label,
            icon: icon,
            selected: picked == option.value,
            onTap: () => onPicked(option.value),
          ),
        );
      }
      widgets.add(
        TextButton(
          onPressed: () => onNotListed(true),
          child: const Text('None of these'),
        ),
      );
    }
    widgets.add(const SizedBox(height: 16));
    return widgets;
  }

  /// Narrow a short list with the council's `q` query.
  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    await context.read<LookupProvider>().refineAddressLookup(query);
  }

  /// The council's option list for a picker field, when it has one for it.
  InputOptions? _optionsFor(AddressField field, AddressLookup lookup) {
    final options = lookup.inputOptions;
    if (options == null) return null;
    final expected = switch (field) {
      AddressField.street => 'street',
      AddressField.locality => 'locality',
      _ => null,
    };
    return options.field == expected ? options : null;
  }

  /// What is still missing, as a message for the user.
  String? _missingField({
    required AddressInputSpec spec,
    required String property,
    required String? street,
    required String? locality,
  }) {
    if (spec.includes(AddressField.property) && property.trim().isEmpty) {
      return 'Enter the first line of your address.';
    }
    if (spec.includes(AddressField.street) && street == null) {
      return 'Enter or pick your street.';
    }
    if (spec.includes(AddressField.locality) && locality == null) {
      return 'Enter or pick your area.';
    }
    if (spec.includes(AddressField.weekday) && _weekday == null) {
      return 'Choose the day your bins are usually collected.';
    }
    if (spec.includes(AddressField.propertyType) && _propertyType == null) {
      return 'Choose the kind of property you live in.';
    }
    return null;
  }

  /// What went wrong, in the user's terms.
  ///
  /// A failed lookup carries its own `detail`; anything else (a refused
  /// request, a dropped connection) goes through [apiErrorCopy] so the API's
  /// own accounting never reaches the user.
  String _errorDetail(LookupProvider provider) {
    final detail = provider.failedLookup?.detail;
    if (detail != null && detail.isNotEmpty) return detail;
    return apiErrorCopy(provider.error!);
  }

  /// The addresses the council offered instead, and only for a failure that
  /// names the address as the problem: an unrelated failure must never suggest
  /// that a different address is the answer.
  List<AddressCandidate> _offeredAddresses(LookupProvider provider) {
    final failed = provider.failedLookup;
    if (failed?.problem != 'address_not_found') return const [];
    return failed!.candidates;
  }

  /// Whether the user may be offered a neighbour's dates.
  ///
  /// Consent is the whole point: only an `opt_in` council may be answered for
  /// on the user's behalf, and only after an address it could not find. An
  /// `automatic` council needs no consent, and an `unavailable` one has
  /// nothing to offer.
  bool _canOfferNeighbour(Lookup? failed, AddressLookup lookup) =>
      failed?.problem == 'address_not_found' &&
      lookup.postcodeRepresentative == 'opt_in';

  Future<void> _openCouncil(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Submit an address the council itself offered, so a failed lookup is not a
  /// reason to retype everything.
  Future<void> _pickCandidate(
    AddressCandidate candidate,
    AddressLookup lookup,
  ) async {
    final provider = context.read<LookupProvider>();
    await provider.selectAddress(candidate, postcode: lookup.postcode);
    if (!mounted) return;
    final schedule = provider.schedule;
    if (schedule == null) return;

    // A provisional answer is a neighbour's dates served while the exact
    // lookup finishes, so it is never kept as the user's own.
    if (!schedule.provisional) {
      final settings = context.read<SettingsProvider>();
      await settings.saveAddress(
        address: candidate.label,
        postcode: lookup.postcode,
        propertyId: candidate.id,
      );
      await settings.saveSchedule(schedule);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
    );
  }

  /// Ask the council to answer for the nearest property to the postcode.
  ///
  /// This is the user's consent, given here, so the result is a neighbour's
  /// dates: it is shown with its provisional label and never persisted.
  Future<void> _useNeighbour(AddressLookup lookup) async {
    final provider = context.read<LookupProvider>();
    await provider.submitWithPostcodeRepresentative(
      postcode: lookup.postcode,
    );
    if (!mounted) return;
    if (provider.schedule == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
    );
  }

  Future<void> _submit(AddressLookup lookup, AddressInputSpec spec) async {
    final property = _propertyController.text;
    final street = resolvedChoice(
      selected: _pickedStreet,
      typed: _streetController.text,
      notListedValue: _optionsFor(AddressField.street, lookup)?.notListedValue,
    );
    final locality = resolvedChoice(
      selected: _pickedLocality,
      typed: _localityController.text,
      notListedValue:
          _optionsFor(AddressField.locality, lookup)?.notListedValue,
    );

    final missing = _missingField(
      spec: spec,
      property: property,
      street: street,
      locality: locality,
    );
    if (missing != null) {
      setState(() => _validationError = missing);
      return;
    }
    setState(() => _validationError = null);

    final provider = context.read<LookupProvider>();
    await provider.submitLookup(
      postcode: lookup.postcode,
      address: buildAddressBody(
        spec: spec,
        property: property,
        street: street,
        locality: locality,
        weekday: _weekday,
        propertyType: _propertyType,
      ),
    );
    if (!mounted) return;

    // A failure is shown on the form itself, with a way back to the postcode
    // screen, so nothing is saved against an address that did not resolve.
    if (provider.error != null) return;
    final schedule = provider.schedule;
    if (schedule == null) return;

    final settings = context.read<SettingsProvider>();
    // A provisional answer is the same postcode's NEIGHBOUR served while the
    // exact lookup is still running: its property id names that neighbour, so
    // saving either the address or the schedule would attach the user to
    // somebody else's bin days. It is shown, with its label and the pending
    // lookup behind it, and nothing is kept.
    if (!schedule.provisional) {
      await settings.saveAddress(
        address: describeAddress(
          postcode: lookup.postcode,
          property: property,
          street: street,
          locality: locality,
        ),
        postcode: lookup.postcode,
        propertyId: schedule.propertyId,
      );
      await settings.saveSchedule(schedule);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
    );
  }
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.teal)
            else
              const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// What went wrong and every honest way forward.
///
/// A failed lookup is not just a message: the council may have offered the
/// addresses it does know, and it may let the user consent to dates from a
/// nearby property. The council's own page comes first, because checking by
/// hand is the one thing that always works.
class _LookupErrorCard extends StatelessWidget {
  const _LookupErrorCard({
    required this.detail,
    required this.candidates,
    required this.offerNeighbour,
    required this.onOpenCouncil,
    required this.onPickCandidate,
    required this.onUseNeighbour,
    required this.onStartOver,
    this.retryCopy,
    this.councilUrl,
  });

  final String detail;

  /// The countdown after a rate-limited answer, when the server gave one.
  final String? retryCopy;

  /// The council's own lookup page, when it has one.
  final String? councilUrl;

  /// The addresses the council offered instead, empty unless the failure says
  /// the address was the problem.
  final List<AddressCandidate> candidates;

  /// Whether the user may consent to dates from a nearby property.
  final bool offerNeighbour;

  final ValueChanged<String> onOpenCouncil;
  final ValueChanged<AddressCandidate> onPickCandidate;
  final VoidCallback onUseNeighbour;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final url = councilUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.softPink,
        border: Border(left: BorderSide(color: AppColors.error, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detail, style: const TextStyle(fontSize: 16)),
          if (retryCopy != null) ...[
            const SizedBox(height: 8),
            Text(retryCopy!, style: const TextStyle(fontSize: 16)),
          ],
          if (url != null) ...[
            TextButton(
              onPressed: () => onOpenCouncil(url),
              child: const Text("Check on your council's site"),
            ),
          ],
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _FieldTitle('Did you mean one of these?'),
            for (final candidate in candidates)
              _ChoiceTile(
                label: candidate.label,
                icon: Icons.home_outlined,
                selected: false,
                onTap: () => onPickCandidate(candidate),
              ),
          ],
          if (offerNeighbour) ...[
            const SizedBox(height: 8),
            const _FieldTitle('Use dates from a nearby property instead?'),
            const Text(
              'Your council cannot find that exact address, so it can answer '
              'for the nearest property on your postcode instead. The dates '
              'may not be yours.',
              style: TextStyle(fontSize: 16),
            ),
            TextButton(
              onPressed: onUseNeighbour,
              child: const Text('Use a nearby property'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onStartOver,
            child: const Text('Try another postcode'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/address_input.dart';
import '../models/address_lookup.dart';
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
                  detail: provider.error!.detail ??
                      'We could not find your bin days.',
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

class _LookupErrorCard extends StatelessWidget {
  const _LookupErrorCard({required this.detail, required this.onStartOver});

  final String detail;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
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

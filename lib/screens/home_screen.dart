import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/postcode.dart';
import '../core/theme.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import '../services/when_is_bins_api.dart';
import 'address_entry_screen.dart';
import 'address_select_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';

/// The start screen: enter a postcode to find your bin day.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _postcodeController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    // The schedule hydration from saved preferences is handled by
    // WhenIsBinApp so it works regardless of which screen is shown.
  }

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  /// Show the saved bin days, restoring them from storage first if this
  /// session has not looked anything up yet.
  void _openSavedSchedule(SettingsProvider settings) {
    context.read<LookupProvider>().restoreSchedule(settings.savedSchedule);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
    );
  }

  Future<void> _submit() async {
    final postcode = UkPostcode.normalise(_postcodeController.text);
    if (postcode.isEmpty) {
      setState(() => _validationError = 'Enter a postcode.');
      return;
    }
    // Checked here, before the network: a value that is not a postcode shape
    // costs nothing to reject, and the user gets the answer immediately.
    if (!UkPostcode.isValid(postcode)) {
      setState(
        () => _validationError =
            'Enter a valid UK postcode, for example CB4 2HX.',
      );
      return;
    }
    setState(() => _validationError = null);

    final lookup = context.read<LookupProvider>();
    await lookup.lookupPostcode(postcode);
    if (!mounted) return;

    if (lookup.error != null) {
      setState(() => _validationError = _errorMessage(lookup.error!));
      return;
    }

    final addressLookup = lookup.addressLookup;
    if (addressLookup == null) return;

    if (addressLookup.candidates.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddressSelectScreen(addressLookup: addressLookup),
        ),
      );
    } else {
      // No candidate list: the council needs an address, a street, an area, a
      // weekday or a property type. The form is driven by the lookup's own
      // `required_input`, so every remaining journey is reachable from here.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddressEntryScreen(addressLookup: addressLookup),
        ),
      );
    }
  }

  String _errorMessage(ApiException e) {
    switch (e.problem) {
      case 'postcode_outside_coverage':
        return 'We could not find a collecting council for that postcode.';
      case 'invalid_postcode':
        return 'Enter a full UK postcode.';
      default:
        return e.detail ?? 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lookup = context.watch<LookupProvider>();
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('when·is·bins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Find your bin day',
              style: TextStyle(
                fontSize: 40,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppColors.inkFor(brightness),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Use this service to:',
              style: TextStyle(fontSize: 24, height: 1.35),
            ),
            const SizedBox(height: 12),
            const _ServiceList(),
            const SizedBox(height: 24),
            if (settings.savedAddress != null) ...[
              _SavedAddressCard(
                address: settings.savedAddress!,
                onView: () => _openSavedSchedule(settings),
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _postcodeController,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Postcode',
                errorText: _validationError,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: lookup.isLoading ? null : _submit,
                child: lookup.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Find my bin day'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This service shows household bin collections. Businesses, public buildings and some new homes usually are not in a council\u2019s household collection records.',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.mutedFor(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceList extends StatelessWidget {
  const _ServiceList();

  @override
  Widget build(BuildContext context) {
    const items = [
      'see which bins go out, and when',
      'get a reminder the evening before',
      'add your bin days to your calendar',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 12),
                  child: CircleAvatar(
                    radius: 5,
                    backgroundColor: AppColors.teal,
                  ),
                ),
                Expanded(
                  child: Text(item, style: const TextStyle(fontSize: 19)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SavedAddressCard extends StatelessWidget {
  const _SavedAddressCard({required this.address, required this.onView});

  final String address;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.softAqua,
        border: Border(left: BorderSide(color: AppColors.teal, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your saved address',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            address,
            style: const TextStyle(fontSize: 16, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onView,
            child: const Text('View your bin days'),
          ),
        ],
      ),
    );
  }
}

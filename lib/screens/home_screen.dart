import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import '../services/when_is_bins_api.dart';
import 'address_select_screen.dart';
import 'schedule_screen.dart';

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
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final postcode = _postcodeController.text.trim().toUpperCase();
    if (postcode.isEmpty) {
      setState(() => _validationError = 'Enter a postcode.');
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
      // No candidate list — the council needs free-text input. For now we
      // surface the required input as a message.
      setState(() {
        _validationError =
            'This council needs more information. Please try again later.';
      });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('when·is·bins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScheduleScreen()),
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
            const Text(
              'Find your bin day',
              style: TextStyle(
                fontSize: 40,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppColors.ink,
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
                onView: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScheduleScreen(),
                    ),
                  );
                },
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
            const Text(
              'This service shows household bin collections. Businesses, public buildings and some new homes usually are not in a council\u2019s household collection records.',
              style: TextStyle(fontSize: 16, color: AppColors.muted),
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
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(address, style: const TextStyle(fontSize: 16)),
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

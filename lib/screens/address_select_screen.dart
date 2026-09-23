import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/address_lookup.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import 'schedule_screen.dart';

/// Lets the user pick their address from the council's candidate list.
class AddressSelectScreen extends StatelessWidget {
  const AddressSelectScreen({super.key, required this.addressLookup});

  final AddressLookup addressLookup;

  @override
  Widget build(BuildContext context) {
    final lookup = context.watch<LookupProvider>();
    final settings = context.read<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Select your address')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select your address',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${addressLookup.council?.name ?? 'Your council'} \u2022 ${addressLookup.postcode}',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.mutedFor(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(height: 24),
            if (lookup.isLoading)
              const Center(child: CircularProgressIndicator())
            else
              for (final candidate in addressLookup.candidates)
                _AddressTile(
                  label: candidate.label,
                  onTap: () async {
                    await lookup.selectAddress(
                      candidate,
                      postcode: addressLookup.postcode,
                    );
                    if (!context.mounted) return;
                    final schedule = lookup.schedule;
                    if (schedule != null) {
                      // Persist the address and its schedule, so the home
                      // screen shortcut works without another lookup.
                      await settings.saveAddress(
                        address: candidate.label,
                        postcode: addressLookup.postcode,
                        propertyId: candidate.id,
                      );
                      await settings.saveSchedule(schedule);
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ScheduleScreen(),
                        ),
                      );
                    } else if (lookup.error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            lookup.error!.detail ??
                                'We could not find your bin days.',
                          ),
                        ),
                      );
                    }
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.label, required this.onTap});

  final String label;
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
            Icon(
              Icons.home_outlined,
              color: AppColors.accentFor(Theme.of(context).brightness),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.mutedFor(Theme.of(context).brightness),
            ),
          ],
        ),
      ),
    );
  }
}

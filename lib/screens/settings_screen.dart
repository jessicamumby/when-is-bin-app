import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/settings_provider.dart';
import '../services/reminder_scheduler.dart';

/// Settings: reminder time choice and saved-address management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Reminder time',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'When should we remind you to put the bins out?',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mutedFor(Theme.of(context).brightness),
            ),
          ),
          const SizedBox(height: 12),
          RadioGroup<ReminderTime>(
            groupValue: settings.reminderTime,
            onChanged: (value) {
              if (value != null) settings.setReminderTime(value);
            },
            child: Column(
              children: [
                RadioListTile<ReminderTime>(
                  title: const Text('Morning before (9:00am)'),
                  value: ReminderTime.morning,
                ),
                RadioListTile<ReminderTime>(
                  title: const Text('Evening before (7:00pm)'),
                  value: ReminderTime.evening,
                ),
              ],
            ),
          ),
          const Divider(height: 40),
          const Text(
            'Saved address',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (settings.savedAddress != null) ...[
            Text(
              settings.savedAddress!,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => settings.clearSavedAddress(),
              child: const Text('Remove saved address'),
            ),
          ] else
            Text(
              'No address saved.',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.mutedFor(Theme.of(context).brightness),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/schedule.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_sync_service.dart';
import 'settings_screen.dart';

/// Shows the bin collection schedule and lets the user set reminders.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _scheduling = false;

  @override
  Widget build(BuildContext context) {
    final lookup = context.watch<LookupProvider>();
    final settings = context.watch<SettingsProvider>();
    final schedule = lookup.schedule;

    if (schedule == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your bin days')),
        body: const Center(
          child: Text('No schedule yet. Search for your postcode first.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your bin days'),
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
              'Your bin days',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            if (settings.savedAddress != null)
              Text(
                settings.savedAddress!,
                style: const TextStyle(fontSize: 16, color: AppColors.muted),
              ),
            const SizedBox(height: 24),
            _NextCollectionCard(schedule: schedule),
            const SizedBox(height: 24),
            _ReminderCard(
              enabled: settings.remindersEnabled,
              scheduling: _scheduling,
              reminderTime: settings.reminderTime,
              onToggle: (value) => _toggleReminders(value, schedule, settings),
              onOpenSettings: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
            if (schedule.calendarUrl != null)
              _CalendarCard(calendarUrl: schedule.calendarUrl!),
            const SizedBox(height: 24),
            const Text(
              'Collection dates come from your council\u2019s own website and can change at short notice.',
              style: TextStyle(fontSize: 16, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReminders(
    bool value,
    Schedule schedule,
    SettingsProvider settings,
  ) async {
    final sync = context.read<ReminderSyncService>();
    setState(() => _scheduling = true);

    try {
      if (value) {
        // Never let the switch claim reminders are on when the OS is going to
        // drop them on the floor.
        final granted = await sync.requestPermissions();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turn on notifications for this app in your device settings to '
                'get bin reminders.',
              ),
            ),
          );
          return;
        }
      }

      // The sync service owns which dates may be reminded about, so the
      // switch and the launch-time re-sync can never disagree.
      await sync.sync(
        schedule: schedule,
        enabled: value,
        reminderTime: settings.reminderTime,
      );
      await settings.setRemindersEnabled(value);
    } finally {
      if (mounted) setState(() => _scheduling = false);
    }
  }
}

class _NextCollectionCard extends StatelessWidget {
  const _NextCollectionCard({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final next = _nextCollectionDate();
    if (next == null) {
      return const _InsetCard(
        child: Text('No upcoming collection dates are available yet.'),
      );
    }
    final date = DateTime.parse(next.date);
    final formatted = DateFormat('EEEE d MMMM yyyy').format(date);
    final bins = next.collections.map((c) => c.name).join(', ');

    return _InsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next collection',
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            formatted,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Put out: $bins',
            style: const TextStyle(fontSize: 19),
          ),
        ],
      ),
    );
  }

  ByDateEntry? _nextCollectionDate() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (final entry in schedule.byDate) {
      if (entry.date.compareTo(today) >= 0) return entry;
    }
    return null;
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.enabled,
    required this.scheduling,
    required this.reminderTime,
    required this.onToggle,
    required this.onOpenSettings,
  });

  final bool enabled;
  final bool scheduling;
  final ReminderTime reminderTime;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final timeLabel = reminderTime == ReminderTime.morning
        ? '9:00am on the day before'
        : '7:00pm on the day before';

    return _InsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remind me to put the bins out',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'You\u2019ll get a notification at $timeLabel.',
            style: const TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: enabled,
                onChanged: scheduling ? null : onToggle,
              ),
              const SizedBox(width: 8),
              if (scheduling)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  enabled ? 'Reminders on' : 'Reminders off',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Change reminder time'),
          ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.calendarUrl});

  final String calendarUrl;

  @override
  Widget build(BuildContext context) {
    return _InsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add to your calendar',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Subscribe to your bin collection calendar feed.',
            style: TextStyle(fontSize: 16, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(calendarUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.calendar_today_outlined),
            label: const Text('Open calendar feed'),
          ),
        ],
      ),
    );
  }
}

class _InsetCard extends StatelessWidget {
  const _InsetCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.softAqua,
        border: Border(left: BorderSide(color: AppColors.teal, width: 6)),
      ),
      child: child,
    );
  }
}

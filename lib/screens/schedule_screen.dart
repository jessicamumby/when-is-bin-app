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
  const ScheduleScreen({super.key, this.forceLight = false});

  /// When true, the screen always renders in the light design system. Used by
  /// onboarding, which is light-only; the main app leaves it false so it
  /// follows the system theme.
  final bool forceLight;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _scheduling = false;

  @override
  Widget build(BuildContext context) {
    final lookup = context.watch<LookupProvider>();
    final settings = context.watch<SettingsProvider>();

    // The Theme must wrap the screen so every Theme.of(context) inside the
    // body resolves the light theme, not the app's dark theme. A Builder
    // re-reads the wrapped context so the body sees the light theme.
    return widget.forceLight
        ? Theme(
            data: AppTheme.light,
            child: Builder(
              builder: (lightContext) =>
                  _buildScreen(lightContext, lookup, settings),
            ),
          )
        : _buildScreen(context, lookup, settings);
  }

  Widget _buildScreen(
    BuildContext context,
    LookupProvider lookup,
    SettingsProvider settings,
  ) {
    final schedule = lookup.schedule;
    final muted = AppColors.mutedFor(Theme.of(context).brightness);

    return schedule == null
        ? Scaffold(
            appBar: AppBar(title: const Text('Your bin days')),
            body: _placeholder(lookup),
          )
        : Scaffold(
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
                      style: TextStyle(fontSize: 16, color: muted),
                    ),
                  const SizedBox(height: 24),
                  _NextCollectionCard(schedule: schedule),
                  const SizedBox(height: 24),
                  _ReminderCard(
                    enabled: settings.remindersEnabled,
                    scheduling: _scheduling,
                    reminderTime: settings.reminderTime,
                    provisional: schedule.provisional,
                    onToggle: (value) =>
                        _toggleReminders(value, schedule, settings),
                    onOpenSettings: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (schedule.calendarUrl != null)
                    _CalendarCard(calendarUrl: schedule.calendarUrl!),
                  const SizedBox(height: 24),
                  Text(
                    'Collection dates come from your council\u2019s own website and can change at short notice.',
                    style: TextStyle(fontSize: 16, color: muted),
                  ),
                ],
              ),
            ),
          );
  }

  /// The screen with nothing to show yet: still loading, failed, or simply
  /// empty. Each one says what happened and offers the next step, instead of
  /// leaving the user on a bare line of text.
  Widget _placeholder(LookupProvider lookup) {
    if (lookup.isLoading) return const _LoadingState();

    final error = lookup.error;
    if (error != null) {
      return _ErrorState(
        detail: error.detail,
        onRetry: _canRetry(lookup) ? () => _retry(lookup) : null,
        onSearch: () => Navigator.of(context).pop(),
      );
    }

    return _EmptyState(onSearch: () => Navigator.of(context).pop());
  }

  static bool _canRetry(LookupProvider lookup) =>
      lookup.pendingLookupId != null || lookup.postcode != null;

  /// Re-run whatever can honestly be re-run: a lookup that was left pending is
  /// reconnected to (never resubmitted), otherwise the postcode is asked for
  /// again, which is the start of the same journey.
  Future<void> _retry(LookupProvider lookup) async {
    if (lookup.pendingLookupId != null) {
      await lookup.continuePendingLookup();
      return;
    }
    final postcode = lookup.postcode;
    if (postcode != null) await lookup.lookupPostcode(postcode);
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
    final caveat = scheduleDateCaveat(schedule);

    return _InsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (schedule.provisional) ...[
            const _ProvisionalLabel(),
            const SizedBox(height: 12),
          ],
          if (caveat != null) ...[
            Text(
              caveat,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.mutedFor(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (next == null)
            const Text('No upcoming collection dates are available yet.')
          else
            _NextCollectionDetails(next: next),
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

/// How much of a council calendar the dates actually are, in the council's own
/// terms. Unknown values say nothing: a caveat nobody can back up is worse
/// than no caveat.
///
/// The completeness of the data is the more specific statement, so it wins —
/// except that a full horizon says nothing about *how* the dates were derived,
/// which the confidence still has to.
String? scheduleDateCaveat(Schedule schedule) {
  return _completenessCaveats[schedule.dateCompleteness] ??
      _confidenceCaveats[schedule.dateConfidence];
}

const Map<String, String> _completenessCaveats = {
  'next_only': 'These dates cover the next collection only.',
  'limited_horizon':
      'Your council has only published dates for the next few '
      'weeks.',
  'weekday_only':
      'Your council publishes the collection weekday only, so the '
      'exact date may change.',
};

const Map<String, String> _confidenceCaveats = {
  'next_collection_only': 'These dates cover the next collection only.',
  'council_projection':
      'This council has not published a full calendar, so '
      'these dates are a projection.',
};

/// The date, the bins, and nothing else.
class _NextCollectionDetails extends StatelessWidget {
  const _NextCollectionDetails({required this.next});

  final ByDateEntry next;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat(
      'EEEE d MMMM yyyy',
    ).format(DateTime.parse(next.date));
    final bins = next.collections.map((c) => c.name).join(', ');
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next collection',
          style: TextStyle(fontSize: 16, color: AppColors.mutedFor(brightness)),
        ),
        const SizedBox(height: 4),
        Text(
          formatted,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.accentFor(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Text('Put out: $bins', style: const TextStyle(fontSize: 19)),
      ],
    );
  }
}

/// An address the council has not confirmed yet: say so plainly, because the
/// dates under it may still move.
class _ProvisionalLabel extends StatelessWidget {
  const _ProvisionalLabel();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ink = AppColors.inkFor(brightness);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.softWarnFor(brightness)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, size: 20, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Provisional \u2014 your address is still being checked',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.enabled,
    required this.scheduling,
    required this.reminderTime,
    required this.provisional,
    required this.onToggle,
    required this.onOpenSettings,
  });

  final bool enabled;
  final bool scheduling;
  final ReminderTime reminderTime;

  /// A provisional address is deliberately excluded from reminders (see
  /// `ReminderSyncService`), so the switch must not claim otherwise.
  final bool provisional;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final timeLabel = reminderTime == ReminderTime.morning
        ? '9:00am on the day before'
        : '7:00pm on the day before';
    final canSchedule = !provisional;

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
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mutedFor(Theme.of(context).brightness),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: enabled,
                onChanged: (scheduling || !canSchedule) ? null : onToggle,
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
                  canSchedule
                      ? (enabled ? 'Reminders on' : 'Reminders off')
                      : 'Reminders need a confirmed address.',
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
          Text(
            'Subscribe to your bin collection calendar feed.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.mutedFor(Theme.of(context).brightness),
            ),
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
    final brightness = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.softCardFor(brightness),
        border: Border(
          left: BorderSide(color: AppColors.accentFor(brightness), width: 6),
        ),
      ),
      child: child,
    );
  }
}

/// Nothing is loaded yet and a lookup is in flight.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          _LoadingMessage(),
        ],
      ),
    );
  }
}

/// Split out so the message can carry the active brightness' token while the
/// spinner stays const.
class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Finding your bin days\u2026',
      style: TextStyle(
        fontSize: 16,
        color: AppColors.mutedFor(Theme.of(context).brightness),
      ),
    );
  }
}

/// No schedule has been looked up yet: say so and offer the search.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return _Placeholder(
      icon: Icons.event_busy_outlined,
      iconColor: AppColors.mutedFor(Theme.of(context).brightness),
      title: 'No schedule yet',
      body: 'Search for your postcode to find your bin days.',
      primary: ElevatedButton(
        onPressed: onSearch,
        child: const Text('Search for your postcode'),
      ),
    );
  }
}

/// The lookup failed: say what happened, offer a retry when there is one, and
/// always leave a way back to the search.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.detail,
    required this.onRetry,
    required this.onSearch,
  });

  /// The council's or API's own words, when it gave any.
  final String? detail;
  final VoidCallback? onRetry;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return _Placeholder(
      icon: Icons.error_outline,
      iconColor: AppColors.errorFor(Theme.of(context).brightness),
      title: 'We could not load your bin days.',
      body: detail ?? 'Check your connection and try again.',
      primary: retry == null
          ? null
          : ElevatedButton(onPressed: retry, child: const Text('Try again')),
      secondary: OutlinedButton(
        onPressed: onSearch,
        child: const Text('Search for your postcode'),
      ),
    );
  }
}

/// The shared shape of the empty and error states: an icon, a headline, a line
/// of explanation and one or two ways forward.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Widget? primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final primaryAction = primary;
    final secondaryAction = secondary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.mutedFor(Theme.of(context).brightness),
              ),
              textAlign: TextAlign.center,
            ),
            if (primaryAction != null) ...[
              const SizedBox(height: 24),
              primaryAction,
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: 12),
              secondaryAction,
            ],
          ],
        ),
      ),
    );
  }
}

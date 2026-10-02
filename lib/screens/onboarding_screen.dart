import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_error_copy.dart';
import '../core/theme.dart';
import '../providers/lookup_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_sync_service.dart';
import 'address_entry_screen.dart';
import 'address_select_screen.dart';

/// First-launch onboarding. Step 1 collects the user's postcode and runs the
/// existing postcode → address → schedule journey to find and save their bin
/// days. Step 2 (shown once a schedule is found) asks when they would prefer
/// a reminder and, on completion, requests notification permission, schedules
/// the reminders, and marks the user as onboarded so the home screen shows on
/// next launch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _postcodeController = TextEditingController();
  String? _validationError;

  /// The countdown that follows a rate-limited message, when the server asked
  /// the app to wait a specific time.
  String? _retryAfterCopy;
  ReminderTime _chosenTime = ReminderTime.evening;

  /// True from the tap on "Turn on reminders" until onboarding completes. The
  /// OS permission dialog and the platform calls behind it take a moment, and
  /// a button that stays live and silent reads as a frozen app — and invites
  /// a second tap that races the first permission request.
  bool _enablingReminders = false;

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  Future<void> _submitPostcode() async {
    final postcode = _postcodeController.text.trim().toUpperCase();
    // A countdown from an earlier attempt must never outlive its message.
    setState(() => _retryAfterCopy = null);
    if (postcode.isEmpty) {
      setState(() => _validationError = 'Enter a postcode.');
      return;
    }
    setState(() => _validationError = null);

    final lookup = context.read<LookupProvider>();
    await lookup.lookupPostcode(postcode);
    if (!mounted) return;

    if (lookup.error != null) {
      final error = lookup.error!;
      setState(() {
        _validationError = apiErrorCopy(error);
        _retryAfterCopy = apiRetryAfterCopy(error.retryAfter);
      });
      return;
    }

    final addressLookup = lookup.addressLookup;
    if (addressLookup == null) return;

    if (addressLookup.candidates.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddressSelectScreen(
            addressLookup: addressLookup,
            forceLight: true,
          ),
        ),
      );
    } else {
      // No candidate list: the council needs an address, a street, an area, a
      // weekday or a property type, or just the postcode itself. The same form
      // the home screen opens handles every one of them.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddressEntryScreen(
            addressLookup: addressLookup,
            forceLight: true,
          ),
        ),
      );
    }
  }

  Future<void> _enableReminders() async {
    if (_enablingReminders) return;
    setState(() => _enablingReminders = true);

    final settings = context.read<SettingsProvider>();
    final reminderSync = context.read<ReminderSyncService>();
    final lookup = context.read<LookupProvider>();

    try {
      await settings.setReminderTime(_chosenTime);
      await settings.setRemindersEnabled(true);

      // Permission is best-effort and bounded by ReminderSyncService: a
      // dialog that never returns a verdict is treated as denied.
      await reminderSync.requestPermissions();

      // Scheduling is not the user's to wait for. It runs after onboarding
      // completes, so a platform call that errors or stalls in a release
      // build can never strand the user here; the launch re-sync and the
      // Settings toggle retry it.
      unawaited(
        reminderSync
            .sync(
              schedule: lookup.schedule,
              enabled: true,
              reminderTime: _chosenTime,
            )
            .catchError((Object _) {
              debugPrint('Reminder scheduling failed after onboarding.');
              return const <Reminder>[];
            }),
      );
    } catch (_) {
      debugPrint('Reminder setup failed; continuing onboarding.');
    } finally {
      // Whatever happened above, the user has finished onboarding.
      await settings.markOnboarded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lookup = context.watch<LookupProvider>();

    // Onboarding always renders in the light design system, regardless of the
    // device's system theme.
    return Theme(
      data: AppTheme.light,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: lookup.schedule != null
                ? _buildReminderStep(settings)
                : _buildPostcodeStep(lookup),
          ),
        ),
      ),
    );
  }

  Widget _buildPostcodeStep(LookupProvider lookup) {
    return Column(
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
          'Enter your postcode to find which bins go out, and when. '
          'Get a reminder the morning or evening before.',
          style: TextStyle(fontSize: 20, height: 1.35),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _postcodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Postcode',
            errorText: _validationError,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _submitPostcode(),
        ),
        if (_retryAfterCopy != null) ...[
          const SizedBox(height: 8),
          Text(
            _retryAfterCopy!,
            style: const TextStyle(fontSize: 16, color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: lookup.isLoading ? null : _submitPostcode,
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
      ],
    );
  }

  Widget _buildReminderStep(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Get bin day reminders',
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
          'When should we remind you?',
          style: TextStyle(fontSize: 24, height: 1.35),
        ),
        const SizedBox(height: 8),
        const Text(
          'You\u2019ll get a notification before each collection to remind '
          'you to put the bins out.',
          style: TextStyle(fontSize: 16, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        RadioGroup<ReminderTime>(
          groupValue: _chosenTime,
          onChanged: (value) {
            if (value != null) setState(() => _chosenTime = value);
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _enablingReminders ? null : _enableReminders,
            child: _enablingReminders
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Turn on reminders'),
          ),
        ),
      ],
    );
  }
}

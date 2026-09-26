import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release-configuration contracts.
///
/// None of the things asserted here are visible to `flutter test`-style widget
/// tests, and all of them are invisible in a debug build — which is exactly how
/// a release APK with no INTERNET permission, a debug-keystore signature and no
/// notification receivers reached a pre-submission review. They are cheap to
/// pin from the files that ship, so they are pinned here.

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

void main() {
  group('Android release configuration', () {
    late String manifest;
    late String gradle;

    setUpAll(() {
      manifest = _read('android/app/src/main/AndroidManifest.xml');
      gradle = _read('android/app/build.gradle.kts');
    });

    test('the manifest that ships declares INTERNET', () {
      // Only src/debug and src/profile declared it, so production builds had no
      // network access at all: every lookup failed.
      expect(
        manifest,
        contains('android.permission.INTERNET'),
        reason: 'the app cannot reach the WhenIsBins API without it',
      );
    });

    test('declares the notification plugin receivers', () {
      // Without these the scheduled reminder broadcasts have no recipient: the
      // alarm fires and no notification is ever posted, silently.
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.'
          'ScheduledNotificationReceiver',
        ),
      );
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.'
          'ScheduledNotificationBootReceiver',
        ),
      );
      expect(
        manifest,
        contains('android.intent.action.BOOT_COMPLETED'),
        reason: 'reminders must survive a reboot',
      );
      expect(
        manifest,
        contains('android.intent.action.MY_PACKAGE_REPLACED'),
        reason: 'reminders must survive an app update',
      );
    });

    test('every declared receiver is unexported', () {
      // Android 12+ requires an explicit exported attribute, and these receive
      // internal broadcasts only.
      final receiverDeclarations = RegExp(r'<receiver[^>]*>')
          .allMatches(manifest)
          .map((m) => m.group(0)!)
          .toList();
      expect(receiverDeclarations, isNotEmpty);
      for (final declaration in receiverDeclarations) {
        expect(
          declaration,
          contains('android:exported="false"'),
          reason: 'unexported: $declaration',
        );
      }
    });

    test('does not pin the activity to an empty task affinity', () {
      // Android's notification permission dialog is delivered to the activity
      // that requested it. `taskAffinity=""` puts MainActivity in its own
      // fresh task, which on recreation mid-request orphans the plugin's
      // onRequestPermissionsResult — the Dart future never resolves and
      // onboarding/looks stuck. The manifest must keep the default affinity.
      expect(
        manifest,
        isNot(contains('android:taskAffinity=""')),
        reason: 'an empty task affinity breaks notification permission results',
      );
    });

    test('does not request the exact-alarm permission it never uses', () {
      // Reminders are scheduled with inexactAllowWhileIdle, so this sensitive
      // permission buys nothing and invites review scrutiny on Play.
      expect(
        _read('lib/services/notification_service.dart'),
        contains('AndroidScheduleMode.inexactAllowWhileIdle'),
        reason: 'if this changed, revisit the permission decision',
      );
      expect(
        manifest,
        isNot(
          contains('android:name="android.permission.SCHEDULE_EXACT_ALARM"'),
        ),
        reason: 'exact alarms are not used',
      );
    });

    test('keeps the saved address out of cloud backups', () {
      // The address and postcode are the user's personal data; auto-backup is
      // on by default and would copy them off the device.
      expect(manifest, contains('android:allowBackup="false"'));
    });

    test('is labelled "When Is Bins"', () {
      expect(manifest, contains('android:label="When Is Bins"'));
    });

    test('signs releases from the upload keystore, with a loud fallback', () {
      expect(
        gradle,
        contains('key.properties'),
        reason: 'release signing should come from the upload keystore',
      );
      expect(
        gradle,
        contains('create("release")'),
        reason: 'a release signing config must be built from those credentials',
      );
      expect(
        gradle,
        contains('hasReleaseSigning'),
        reason: 'the debug keystore must only be reachable when key.properties '
            'is absent — never as the unconditional release signing config',
      );
      expect(
        gradle,
        contains('DEBUG keystore'),
        reason: 'the fallback must announce itself: Play rejects a '
            'debug-signed upload and nothing else in the build would say so',
      );
    });

    test('signing secrets are gitignored', () {
      final ignore = _read('.gitignore');
      for (final pattern in const ['key.properties', '*.jks', '*.keystore']) {
        expect(
          ignore,
          contains(pattern),
          reason: '$pattern must never be committed',
        );
      }
    });

    test('key.properties.example documents the signing keys', () {
      final example = _read('android/key.properties.example');
      for (final key in const [
        'storePassword',
        'keyPassword',
        'keyAlias',
        'storeFile',
      ]) {
        expect(example, contains(key));
      }
    });
  });

  group('iOS release configuration', () {
    late String plist;
    late String project;

    setUpAll(() {
      plist = _read('ios/Runner/Info.plist');
      project = _read('ios/Runner.xcodeproj/project.pbxproj');
    });

    test('ships an app privacy manifest into the built bundle', () {
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(
        project,
        contains('PrivacyInfo.xcprivacy'),
        reason: 'an asset not in the project is not copied into the .app',
      );
      expect(manifest, contains('NSPrivacyTracking'));
    });

    test('declares no tracking and no tracking domains', () {
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest, contains('<key>NSPrivacyTracking</key>'));
      expect(manifest, contains('<false/>'));
      expect(manifest, contains('NSPrivacyTrackingDomains'));
    });

    test('declares the required-reason APIs the app uses', () {
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest, contains('NSPrivacyAccessedAPITypes'));
      // UserDefaults, via the saved address and reminder settings.
      expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    });

    test('declares its encryption use so upload does not prompt', () {
      // The entry carries a comment explaining it, so compare the markup only.
      final markup =
          plist.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final index = markup.indexOf('ITSAppUsesNonExemptEncryption');
      expect(index, isNot(-1));
      expect(
        markup.substring(index, index + 60).replaceAll(RegExp(r'\s+'), ''),
        contains('<false/>'),
        reason: 'the app is HTTPS-only, so use of encryption is exempt',
      );
    });

    test('declares the address it sends to the API', () {
      // The postcode and chosen address are transmitted to whenisbins.com to
      // resolve a schedule, so "nothing is collected" would be untrue.
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest, contains('NSPrivacyCollectedDataTypePhysicalAddress'));
      expect(
        manifest,
        contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'),
      );
      expect(manifest, contains('NSPrivacyCollectedDataTypeTracking'));
    });

    test('is displayed as "When Is Bins"', () {
      expect(plist, contains('<string>When Is Bins</string>'));
    });
  });

  group('Release hygiene', () {
    test('every font family the theme asks for is actually bundled', () {
      // The theme requested LexendDeca while no font was bundled anywhere, so
      // the app silently rendered in the platform default.
      final theme = _read('lib/core/theme.dart');
      final families = RegExp(r"fontFamily:\s*'([^']+)'")
          .allMatches(theme)
          .map((m) => m.group(1)!)
          .toSet();
      expect(families, isNotEmpty, reason: 'no font family is set at all');

      final pubspec = _read('pubspec.yaml');
      for (final family in families) {
        expect(
          pubspec,
          contains('family: $family'),
          reason: '$family is used by the theme but not declared in pubspec',
        );
      }
    });

    test('the bundled font ships its licence', () {
      expect(
        File('assets/fonts/OFL.txt').existsSync(),
        isTrue,
        reason: 'Lexend Deca is OFL-licensed and the licence must travel '
            'with the font',
      );
    });

    test('the throwaway notification proof entrypoint is gone', () {
      // A debug harness in lib/ is one -t flag away from being built as the
      // shipped app entrypoint.
      expect(
        File('lib/proof_multi_bin_notifications.dart').existsSync(),
        isFalse,
      );
    });

    test('CI builds a release bundle and guards what ships', () {
      final ci = _read('.github/workflows/ci.yml');
      expect(
        ci,
        contains('appbundle'),
        reason: 'a release build in CI is what catches manifest and signing '
            'mistakes before upload',
      );
      expect(
        ci,
        contains('android.permission.INTERNET'),
        reason: 'CI should assert the permission is in the built artifact',
      );
    });
  });
}
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for the verify-when-is-bin skill.
///
/// Writes every `binding.takeScreenshot(name)` from the device into `RUN_DIR`
/// (an absolute path), so proof lands in the run directory, not the repo.
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final dir = Platform.environment['RUN_DIR'] ?? 'build/verify';
        final file = File('$dir/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        return true;
      },
    );

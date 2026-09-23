import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Guard rails for the platform launcher/tile artwork.
///
/// The icons themselves are binary assets, so the thing worth pinning down in
/// tests is that every file the platform manifests and the iOS asset catalogue
/// point at actually exists, is a real PNG, and is the pixel size that platform
/// expects. A missing or mis-sized icon otherwise only shows up as a blank
/// square on a device — or as an App Store rejection.

const _androidRes = 'android/app/src/main/res';
const _iosAppIconSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

/// Density bucket -> scale factor, matching Android's density qualifiers.
const _androidScales = <String, double>{
  'mipmap-mdpi': 1,
  'mipmap-hdpi': 1.5,
  'mipmap-xhdpi': 2,
  'mipmap-xxhdpi': 3,
  'mipmap-xxxhdpi': 4,
};

/// Adaptive icon layers are 108dp, so their bitmaps are 108 * scale px.
const _adaptiveLayerDp = 108;

/// A legacy launcher icon bitmap is 48dp.
const _legacyLauncherDp = 48;

/// The adaptive-icon layer drawables the XML must wire up.
const _adaptiveLayers = <String>[
  'ic_launcher_background',
  'ic_launcher_foreground',
  'ic_launcher_monochrome',
];

class _Png {
  const _Png(this.width, this.height, this.colourType);

  final int width;
  final int height;

  /// 0 = grey, 2 = RGB, 3 = palette, 4 = grey+alpha, 6 = RGBA.
  final int colourType;

  bool get hasAlphaChannel => colourType == 4 || colourType == 6;
}

/// Reads the IHDR chunk without decoding any pixels.
_Png _readPng(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  final bytes = file.readAsBytesSync();
  expect(
    bytes.length,
    greaterThan(24),
    reason: '$path is too small to contain a PNG header',
  );
  expect(
    bytes.sublist(0, 8),
    orderedEquals(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    reason: '$path is not a PNG',
  );
  final header = ByteData.sublistView(bytes);
  return _Png(header.getUint32(16), header.getUint32(20), bytes[25]);
}

void _expectSquarePng(String path, int expectedSide) {
  final png = _readPng(path);
  expect(png.width, expectedSide, reason: '$path width');
  expect(png.height, expectedSide, reason: '$path height');
}

void main() {
  group('Android launcher icons', () {
    test('the manifest points the launcher at @mipmap/ic_launcher', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest,
        contains('android:icon="@mipmap/ic_launcher"'),
        reason: 'the launcher icon should resolve through the mipmap set',
      );
    });

    test('a legacy launcher icon is present at every density', () {
      _androidScales.forEach((bucket, scale) {
        _expectSquarePng(
          '$_androidRes/$bucket/ic_launcher.png',
          (_legacyLauncherDp * scale).round(),
        );
      });
    });

    test('an adaptive icon XML wires up background, foreground and monochrome',
        () {
      final xml = File('$_androidRes/mipmap-anydpi-v26/ic_launcher.xml');
      expect(
        xml.existsSync(),
        isTrue,
        reason: 'adaptive icons need mipmap-anydpi-v26/ic_launcher.xml',
      );
      final contents = xml.readAsStringSync();
      expect(contents, contains('<adaptive-icon'));
      for (final layer in _adaptiveLayers) {
        expect(
          contents,
          contains('android:drawable="@mipmap/$layer"'),
          reason: 'the adaptive icon should reference $layer',
        );
      }
    });

    test('every adaptive icon layer is present and correctly sized', () {
      _androidScales.forEach((bucket, scale) {
        for (final layer in _adaptiveLayers) {
          _expectSquarePng(
            '$_androidRes/$bucket/$layer.png',
            (_adaptiveLayerDp * scale).round(),
          );
        }
      });
    });

    test('adaptive icon layers keep transparency where it is meaningful', () {
      // The foreground and monochrome layers are composited over the
      // background, so they must not be flattened to opaque bitmaps.
      for (final layer in const ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
        final png = _readPng('$_androidRes/mipmap-xxxhdpi/$layer.png');
        expect(
          png.hasAlphaChannel,
          isTrue,
          reason: '$layer needs an alpha channel to composite correctly',
        );
      }
    });
  });

  group('iOS app icons', () {
    late Map<String, dynamic> catalogue;
    late List<Map<String, dynamic>> entries;

    setUpAll(() {
      final file = File('$_iosAppIconSet/Contents.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the AppIcon set needs a Contents.json',
      );
      catalogue = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      entries = (catalogue['images'] as List)
          .cast<Map<String, dynamic>>()
          .where((entry) => entry['filename'] != null)
          .toList();
    });

    test('the catalogue describes at least the full iPhone icon matrix', () {
      expect(entries, isNotEmpty);
      final idioms = entries.map((e) => e['idiom']).toSet();
      expect(idioms, containsAll(<String>['iphone', 'ipad', 'ios-marketing']));
    });

    test('every catalogue entry resolves to a real PNG', () {
      for (final entry in entries) {
        final png = _readPng('$_iosAppIconSet/${entry['filename']}');
        expect(png.width, greaterThan(0));
      }
    });

    test('each icon matches the size its catalogue entry declares', () {
      for (final entry in entries) {
        final side = double.parse((entry['size'] as String).split('x').first);
        final scale = double.parse((entry['scale'] as String).replaceAll('x', ''));
        final expected = (side * scale).round();
        _expectSquarePng(
          '$_iosAppIconSet/${entry['filename']}',
          expected,
        );
      }
    });

    test('the App Store marketing icon is 1024x1024', () {
      final marketing = entries.singleWhere(
        (e) => e['idiom'] == 'ios-marketing',
        orElse: () => throw StateError('no ios-marketing icon declared'),
      );
      _expectSquarePng('$_iosAppIconSet/${marketing['filename']}', 1024);
    });

    test('no iOS app icon carries an alpha channel', () {
      // App Store Connect rejects icons whose PNGs have an alpha channel, even
      // when every pixel is fully opaque.
      for (final entry in entries) {
        final png = _readPng('$_iosAppIconSet/${entry['filename']}');
        expect(
          png.hasAlphaChannel,
          isFalse,
          reason: '${entry['filename']} has an alpha channel '
              '(colour type ${png.colourType})',
        );
      }
    });

    test('no stale Flutter-template icons are left behind', () {
      final strays = Directory(_iosAppIconSet)
          .listSync()
          .map((entity) => entity.uri.pathSegments.last)
          .where((name) => name.startsWith('Icon-App-'))
          .toList();
      expect(
        strays,
        isEmpty,
        reason: 'the default Flutter icons are no longer referenced',
      );
    });
  });
}
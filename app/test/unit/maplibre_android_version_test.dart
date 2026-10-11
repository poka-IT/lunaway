import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MainActivity calls MapLibre Android itself (the labels' fades of the
/// guidance's map), compiled against the version named in
/// android/app/build.gradle.kts while maplibre_gl brings the library at run
/// time: a bump of the plugin must move that version with it, or a call
/// may be missing at run time.
void main() {
  test('the app compiles against the MapLibre Android maplibre_gl brings', () {
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final plugin = (config['packages']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
      (p) => p['name'] == 'maplibre_gl',
    );
    // A package's root, absolute or relative to .dart_tool/, as a folder.
    final given = plugin['rootUri']! as String;
    final root = Uri.file('${Directory.current.path}/.dart_tool/')
        .resolve(given.endsWith('/') ? given : '$given/');
    final pluginGradle = File.fromUri(root.resolve('android/build.gradle')).readAsStringSync();
    final appGradle = File('android/app/build.gradle.kts').readAsStringSync();
    final sdk = RegExp(r'org\.maplibre\.gl:android-sdk-opengl:([0-9.]+)');
    final brought = sdk.firstMatch(pluginGradle)?.group(1);
    final named = sdk.firstMatch(appGradle)?.group(1);
    expect(
      brought,
      isNotNull,
      reason: "maplibre_gl's android/build.gradle names no MapLibre version",
    );
    expect(named, brought);
  });
}

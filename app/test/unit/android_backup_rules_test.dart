import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';

/// Device backups carry the user's own database and nothing else: the place
/// cache and the demo stores are downloaded or generated again, so they
/// would only fill the user's backup quota. Android leaves them out through
/// its backup rules, iOS and macOS by their caches directory.
void main() {
  const res = 'android/app/src/main/res/xml';
  // The file UserDatabase.open writes (favourites, settings, vehicle
  // profile; drift_flutter appends .sqlite to its name) and the files SQLite
  // keeps beside it during a write.
  const userDatabase = 'lunaway_user.sqlite';
  const expected = {
    'file:$userDatabase',
    'file:$userDatabase-wal',
    'file:$userDatabase-shm',
    'file:$userDatabase-journal',
  };

  String withoutComments(String xml) => xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  /// `domain:path` of every <include> or <exclude> in [xml], by element name.
  Map<String, Set<String>> rules(String xml) {
    final found = <String, Set<String>>{};
    for (final m in RegExp(r'<(include|exclude)\b([^>]*)/?>').allMatches(xml)) {
      String attr(String name) =>
          RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(m.group(2)!)?.group(1) ?? '';
      found.putIfAbsent(m.group(1)!, () => {}).add('${attr('domain')}:${attr('path')}');
    }
    return found;
  }

  /// The body of `<tag ...>...</tag>` in [xml], or null.
  String? section(String xml, String tag) =>
      RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>').firstMatch(xml)?.group(1);

  test('the manifest points Android at both rule files', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(application, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(application, contains('android:fullBackupContent="@xml/backup_rules"'));
    // allowBackup="false" would silently drop the favourites from every backup.
    expect(application, isNot(contains('android:allowBackup="false"')));
  });

  for (final tag in ['cloud-backup', 'device-transfer']) {
    test('Android 12 and later: $tag includes the user database only', () {
      final xml = withoutComments(File('$res/data_extraction_rules.xml').readAsStringSync());
      final body = section(xml, tag);
      expect(body, isNotNull, reason: 'no <$tag> section: Android would back up every file');
      expect(rules(body!), {'include': expected});
    });
  }

  test('Android 11 and earlier: full backup includes the user database only', () {
    final xml = withoutComments(File('$res/backup_rules.xml').readAsStringSync());
    final body = section(xml, 'full-backup-content');
    expect(body, isNotNull);
    expect(rules(body!), {'include': expected});
  });

  test('Android 9 to 11: the cloud copy needs an encrypted backup, the transfer does not', () {
    final xml = withoutComments(File('$res/backup_rules.xml').readAsStringSync());
    // Android reads each <include> on its own: a file goes out when the
    // backup carries every flag that line requires.
    final byFlag = <String, Set<String>>{};
    for (final m in RegExp(r'<include\b([^>]*)/?>').allMatches(xml)) {
      String attr(String name) =>
          RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(m.group(1)!)?.group(1) ?? '';
      byFlag.putIfAbsent(attr('requireFlags'), () => {}).add('${attr('domain')}:${attr('path')}');
    }
    expect(byFlag, {'clientSideEncryption': expected, 'deviceToDeviceTransfer': expected});
  });

  test('Android 12 and later: the cloud copy needs an encrypted backup', () {
    final xml = withoutComments(File('$res/data_extraction_rules.xml').readAsStringSync());
    expect(
      RegExp(r'<cloud-backup\b[^>]*>').firstMatch(xml)!.group(0),
      contains('disableIfNoEncryptionCapabilities="true"'),
    );
  });

  test('neither the place cache nor the demo stores are named', () {
    for (final file in ['data_extraction_rules.xml', 'backup_rules.xml']) {
      final xml = withoutComments(File('$res/$file').readAsStringSync());
      for (final store in ['lunaway.sqlite', 'lunaway_demo.sqlite', 'lunaway_user_demo.sqlite']) {
        expect(xml, isNot(contains('"$store')), reason: '$store in $file');
      }
    }
  });

  test('on iOS and macOS the place cache lives where their backups do not reach', () {
    expect(CacheDatabase.keptInCaches(TargetPlatform.iOS), isTrue);
    expect(CacheDatabase.keptInCaches(TargetPlatform.macOS), isTrue);
    expect(
      CacheDatabase.keptInCaches(TargetPlatform.android),
      isFalse,
      reason: 'Android leaves it out through the rules above',
    );
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _log = Logger('outbox');

PendingFiles platformPendingFiles(UserDatabase db) => IoPendingFiles(
  getApplicationSupportDirectory,
  excludeFromBackup: defaultTargetPlatform == TargetPlatform.iOS ? _excludeOnIos : null,
);

const _files = MethodChannel('lunaway/files');

Future<void> _excludeOnIos(String path) async {
  try {
    await _files.invokeMethod<bool>('excludeFromBackup', path);
  } on Object catch (e) {
    _log.warning('the photos waiting to be sent may go to the backups: $e');
  }
}

/// Files under `outbox/` in the app's support directory, out of reach of
/// other apps and out of the device backups: Android's backup rules list
/// the user database only, and on iOS the folder is marked excluded from
/// the iCloud and computer backups. A photo waiting to be sent is the
/// user's to send, not a copy to restore on another phone.
final class IoPendingFiles implements PendingFiles {
  new(this._root, {Future<void> Function(String path)? excludeFromBackup})
    : _exclude = excludeFromBackup;

  final Future<Directory> Function() _root;
  final Future<void> Function(String path)? _exclude;
  Future<Directory>? _made;

  Future<Directory> _dir() => _made ??= () async {
    try {
      final dir = Directory(p.join((await _root()).path, 'outbox'));
      if (!dir.existsSync()) await dir.create(recursive: true);
      // On every start: a folder made by an earlier version is marked too.
      await _exclude?.call(dir.path);
      return dir;
    } on Object {
      // Tried again at the next call rather than failing the whole run.
      _made = null;
      rethrow;
    }
  }();

  Future<File> _file(String id) async {
    // Ids are hex, made by newFileId: anything else never names a file.
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) throw ArgumentError('not a file id: $id');
    return File(p.join((await _dir()).path, '$id.jpg'));
  }

  @override
  Future<String> put(Uint8List bytes) async {
    final id = newFileId();
    final file = await _file(id);
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    return id;
  }

  @override
  Future<Uint8List?> read(String id) async {
    final file = await _file(id);
    return file.existsSync() ? await file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String id) async {
    final file = await _file(id);
    if (file.existsSync()) await file.delete();
  }
}

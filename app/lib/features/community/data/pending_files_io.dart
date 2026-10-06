import 'dart:io';
import 'dart:typed_data';

import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

PendingFiles platformPendingFiles(UserDatabase db) =>
    IoPendingFiles(getApplicationSupportDirectory);

/// Files under `outbox/` in the app's support directory: out of the
/// Android backups (their rules list the user database only), out of reach
/// of other apps.
final class IoPendingFiles implements PendingFiles {
  new(this._root);

  final Future<Directory> Function() _root;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _root()).path, 'outbox'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String id) async {
    // Ids are hex, made by newFileId: anything else never names a file.
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id))
      throw ArgumentError('not a file id: $id');
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

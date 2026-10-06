import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/features/community/data/pending_files.dart';

PendingFiles platformPendingFiles(UserDatabase db) => DriftPendingFiles(db);

/// The web has no files: the photos wait in the user database, which the
/// browser keeps for the site.
final class DriftPendingFiles implements PendingFiles {
  new(this._db);

  final UserDatabase _db;

  @override
  Future<String> put(Uint8List bytes) async {
    final id = newFileId();
    await _db.into(_db.outboxFiles).insert(OutboxFilesCompanion.insert(id: id, bytes: bytes));
    return id;
  }

  @override
  Future<Uint8List?> read(String id) async =>
      (await (_db.select(_db.outboxFiles)..where((f) => f.id.equals(id))).getSingleOrNull())?.bytes;

  @override
  Future<void> delete(String id) =>
      (_db.delete(_db.outboxFiles)..where((f) => f.id.equals(id))).go();
}

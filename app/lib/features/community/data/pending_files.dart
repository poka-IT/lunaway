import 'dart:math';
import 'dart:typed_data';

/// The bytes of the photos waiting in the outbox. Native builds keep them
/// as files in the app's support directory, which the device backups leave
/// out; the web keeps them in its database (`pending_files_web.dart`).
abstract interface class PendingFiles {
  /// Keeps [bytes] and returns their id.
  Future<String> put(Uint8List bytes);

  /// Null when the file is gone.
  Future<Uint8List?> read(String id);

  Future<void> delete(String id);
}

/// Files in memory: the tests.
final class MemoryPendingFiles implements PendingFiles {
  final Map<String, Uint8List> files = {};
  var _next = 0;

  @override
  Future<String> put(Uint8List bytes) async {
    final id = 'file-${_next++}';
    files[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> read(String id) async => files[id];

  @override
  Future<void> delete(String id) async => files.remove(id);
}

/// A name for a new file: random, so two never meet.
String newFileId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

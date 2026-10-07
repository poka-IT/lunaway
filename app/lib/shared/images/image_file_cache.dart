import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _log = Logger('images');

/// Image bytes kept in the app's cache directory, so a photo seen once shows
/// again without network. The system may clear this directory when space
/// runs out; nothing breaks then, the photo is fetched again. A cache that
/// cannot be used (no cache directory, a full disk) only costs the copy: the
/// photo still shows.
Future<Directory?> _dir() async {
  try {
    final dir = Directory('${(await getApplicationCacheDirectory()).path}/images');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  } on Exception catch (e) {
    _log.fine('no image cache: $e');
    return null;
  }
}

Future<Uint8List?> readCachedImage(String key) async {
  final dir = await _dir();
  if (dir == null) return null;
  final file = File('${dir.path}/$key');
  try {
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    // Seen again: its copy counts from now ([pruneCachedImages]). A date
    // that cannot be written costs nothing of the photo read.
    unawaited(
      file.setLastModified(DateTime.now()).catchError((Object e) {
        _log.fine('image date not refreshed: $e');
      }),
    );
    return bytes;
  } on FileSystemException catch (e) {
    _log.fine('image cache read failed: $e');
    return null;
  }
}

Future<void> writeCachedImage(String key, Uint8List bytes) async {
  final dir = await _dir();
  if (dir == null) return;
  final file = File('${dir.path}/$key');
  // Written aside then renamed, so a crash never leaves half an image.
  final partial = File('${file.path}.part');
  try {
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  } on FileSystemException catch (e) {
    _log.fine('image cache write failed: $e');
  }
}

/// How long a photo not seen again stays: like the pages it belongs to.
const imagesKeep = Duration(days: 90);

/// Removes the photos not shown for [imagesKeep]: each is a trace of a
/// place the user looked at. [dir] for a test; the cache's folder
/// otherwise. In an isolate of its own: a few thousand files are read at
/// every start. Returns how many went.
Future<int> pruneCachedImages(DateTime now, {Directory? dir}) async {
  final folder = dir ?? await _dir();
  if (folder == null) return 0;
  final path = folder.path;
  final cutoff = now.subtract(imagesKeep);
  try {
    return await Isolate.run(() => _prune(path, cutoff));
  } on FileSystemException catch (e) {
    _log.fine('image cache pruning stopped: $e');
    return 0;
  }
}

int _prune(String path, DateTime cutoff) {
  final folder = Directory(path);
  if (!folder.existsSync()) return 0;
  var removed = 0;
  for (final entry in folder.listSync()) {
    if (entry is File && entry.lastModifiedSync().isBefore(cutoff)) {
      entry.deleteSync();
      removed++;
    }
  }
  return removed;
}

import 'dart:io';
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
    return file.existsSync() ? await file.readAsBytes() : null;
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

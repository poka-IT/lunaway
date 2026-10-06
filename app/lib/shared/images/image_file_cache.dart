import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Image bytes kept in the app's cache directory, so a photo seen once shows
/// again without network. The system may clear this directory when space
/// runs out; nothing breaks then, the photo is fetched again.
Future<Directory> _dir() async {
  final dir = Directory('${(await getApplicationCacheDirectory()).path}/images');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

Future<Uint8List?> readCachedImage(String key) async {
  final file = File('${(await _dir()).path}/$key');
  return file.existsSync() ? await file.readAsBytes() : null;
}

Future<void> writeCachedImage(String key, Uint8List bytes) async {
  final file = File('${(await _dir()).path}/$key');
  // Written aside then renamed, so a crash never leaves half an image.
  final partial = File('${file.path}.part');
  await partial.writeAsBytes(bytes, flush: true);
  await partial.rename(file.path);
}

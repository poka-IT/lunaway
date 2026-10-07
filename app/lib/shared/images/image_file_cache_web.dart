import 'dart:typed_data';

/// On the web the browser's HTTP cache keeps the images; nothing to do here.
Future<Uint8List?> readCachedImage(String key) async => null;

Future<void> writeCachedImage(String key, Uint8List bytes) async {}

/// Nothing kept, nothing to remove.
Future<int> pruneCachedImages(DateTime now) async => 0;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:web/web.dart' as web;

PhotoPreparer platformPhotoPreparer() => const CanvasPhotoPreparer();

/// The browser decodes and turns the picture (EXIF orientation applied by
/// `createImageBitmap`), draws it at its size on a canvas and encodes a
/// JPEG: native code, no metadata, and no address of the picture ever
/// made (a `blob:` URL would need the CSP to allow it).
final class CanvasPhotoPreparer implements PhotoPreparer {
  const new();

  @override
  Future<PreparedPhoto> prepare(Uint8List original) async {
    final web.ImageBitmap bitmap;
    try {
      bitmap = await web.window.createImageBitmap(web.Blob([original.toJS].toJS)).toDart;
    } on Object catch (e) {
      throw UnreadablePhotoException('$e');
    }
    final scale = min(1, PhotoPreparer.maxSide / max(bitmap.width, bitmap.height));
    final width = max(1, (bitmap.width * scale).round());
    final height = max(1, (bitmap.height * scale).round());
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D
      // A transparent picture lands on white, as the server would flatten it.
      ..fillStyle = 'white'.toJS
      ..fillRect(0, 0, width, height)
      ..drawImage(bitmap, 0, 0, width, height);
    bitmap.close();
    final done = Completer<web.Blob?>();
    void onBlob(web.Blob? blob) => done.complete(blob);
    canvas.toBlob(onBlob.toJS, 'image/jpeg', (PhotoPreparer.quality / 100).toJS);
    final blob = await done.future;
    context.clearRect(0, 0, width, height);
    if (blob == null) throw const UnreadablePhotoException('the browser made no JPEG');
    final buffer = await blob.arrayBuffer().toDart;
    return PreparedPhoto(jpeg: buffer.toDart.asUint8List(), width: width, height: height);
  }
}

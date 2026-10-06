import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:lunaway/features/community/data/picture_picker.dart';
import 'package:web/web.dart' as web;

PicturePicker platformPicturePicker() => const InputPicturePicker();

/// A file input, read straight into memory: no `blob:` address is made, so
/// the page's CSP (which allows no `blob:` connection) has nothing to block.
final class InputPicturePicker implements PicturePicker {
  const new();

  @override
  bool offers(PictureSource source) => source == PictureSource.gallery;

  @override
  Future<Uint8List?> pick(PictureSource source) {
    final done = Completer<Uint8List?>();
    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = 'image/jpeg,image/png,image/webp,image/heic,image/*';
    void onChange(web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      unawaited(
        file.arrayBuffer().toDart.then(
          (buffer) {
            if (!done.isCompleted) done.complete(buffer.toDart.asUint8List());
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
        ),
      );
    }

    void onCancel(web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }

    input
      ..onchange = onChange.toJS
      ..oncancel = onCancel.toJS
      ..click();
    return done.future;
  }
}

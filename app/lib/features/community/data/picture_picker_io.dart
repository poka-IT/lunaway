import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/data/picture_picker.dart';

final _log = Logger('photos');

PicturePicker platformPicturePicker() => const SystemPicturePicker();

/// The system's own camera and photo picker (Android's photo picker, iOS's
/// PHPicker), or a file dialog on a desktop: the app asks for no access to
/// the whole library. On iOS the picker already shrinks the picture and
/// turns HEIC into JPEG, natively, before Dart sees it.
final class SystemPicturePicker implements PicturePicker {
  const new();

  static bool get _phone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool offers(PictureSource source) =>
      source == PictureSource.gallery || _phone;

  @override
  Future<Uint8List?> pick(PictureSource source) async {
    // On Android, a size or a quality makes the picker keep a full copy of
    // the original in the app's cache beside the scaled one, EXIF included:
    // it gets neither, and the one copy it makes is removed below; the
    // preparer shrinks it. iOS keeps them, which also turn HEIC into JPEG.
    final scaled = defaultTargetPlatform == TargetPlatform.iOS;
    final file = await ImagePicker().pickImage(
      source: source == PictureSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: scaled ? PhotoPreparer.maxSide.toDouble() : null,
      maxHeight: scaled ? PhotoPreparer.maxSide.toDouble() : null,
      imageQuality: scaled ? 92 : null,
      // No location or other metadata asked of the library.
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (_phone) {
      // The picker's own copy, in the app's cache: it may keep the position
      // the photo was taken at, and the bytes are read now. (On a desktop
      // the path is the user's own file, which stays.)
      try {
        await File(file.path).delete();
      } on FileSystemException catch (e) {
        _log.info('the picked copy was not removed: $e');
      }
    }
    return bytes;
  }
}

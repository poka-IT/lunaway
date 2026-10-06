import 'dart:typed_data';

/// Where a picture comes from.
enum PictureSource { camera, gallery }

/// Picks a picture and returns its bytes; null when the user cancels.
abstract interface class PicturePicker {
  /// Whether [source] exists here (no camera on a desktop or in a browser).
  bool offers(PictureSource source);

  Future<Uint8List?> pick(PictureSource source);
}

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A photo ready to send: a JPEG turned the right way up, at most
/// [PhotoPreparer.maxSide] pixels on its long side, with no metadata at all
/// (no position, no date, no camera model).
@immutable
final class PreparedPhoto {
  const new({required this.jpeg, required this.width, required this.height});

  final Uint8List jpeg;
  final int width;
  final int height;
}

/// The device cannot read the picture (a format this platform does not
/// decode).
final class UnreadablePhotoException implements Exception {
  const new(this.reason);

  final String reason;

  @override
  String toString() => 'UnreadablePhotoException: $reason';
}

/// Turns a picked picture into what the API takes. The server re-encodes
/// every photo from its pixels anyway; preparing it here sends a few
/// hundred kilobytes instead of several megabytes over mobile data, keeps
/// the upload within the proxy's time limit, and strips the metadata before
/// anything leaves the device.
abstract interface class PhotoPreparer {
  /// The long side sent: the server keeps 2048 pixels, a little more gives
  /// its resampling something to work with.
  static const maxSide = 2560;

  /// JPEG quality of what is sent.
  static const quality = 85;

  Future<PreparedPhoto> prepare(Uint8List original);
}

import 'package:flutter/services.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/offline/data/pack_files_web.dart'
    as platform;

/// The files of the offline maps on the device: the packs, the parts being
/// downloaded, the index of both, a copy of the last manifest, and the
/// glyphs and sprites the offline styles name. Android and iOS only: the
/// web reads its map online, and the desktop map page reads no local file.
abstract interface class PackFiles {
  /// The platform's own, or an empty stand-in where there is none.
  factory platformFiles() => platform.platformPackFiles();

  /// Whether this platform keeps maps offline.
  bool get supported;

  /// The folder of everything here, absolute, made on first use.
  Future<String> directory();

  /// The index (installed packs and downloads), as written last; null
  /// before the first.
  Future<String?> readIndex();

  Future<void> writeIndex(String json);

  Future<String?> readManifestCopy();

  Future<void> writeManifestCopy(String text);

  /// Where the bytes of [fileName] go while it downloads.
  PackSink partSink(String fileName);

  /// The SHA-256 of the part of [fileName], computed off the UI thread.
  Future<String> partSha256(String fileName);

  /// Moves the finished part of [fileName] into place.
  Future<void> install(String fileName);

  /// Removes [fileName] and its part, if any.
  Future<void> delete(String fileName);

  /// Whether the installed [fileName] is there.
  Future<bool> exists(String fileName);

  /// Bytes taken by the packs and the parts.
  Future<int> usedBytes();

  /// Bytes free on the volume of the packs; null when the platform does
  /// not say.
  Future<int?> freeBytes();

  /// Copies the glyphs and sprites of [bundle] (`assets/map/offline/`) next
  /// to the packs, once per app version, and answers their folder.
  Future<String> installStyleAssets(AssetBundle bundle, {required String version});
}

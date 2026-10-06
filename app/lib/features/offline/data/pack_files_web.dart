import 'package:flutter/services.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files.dart';

/// The web keeps no map offline: its map needs the network.
PackFiles platformPackFiles() => const _NoPackFiles();

final class _NoPackFiles implements PackFiles {
  const new();

  @override
  bool get supported => false;

  Never _no() => throw UnsupportedError('no offline maps on the web');

  @override
  Future<String> directory() async => _no();

  @override
  Future<String?> readIndex() async => null;

  @override
  Future<void> writeIndex(String json) async => _no();

  @override
  Future<String?> readManifestCopy() async => null;

  @override
  Future<void> writeManifestCopy(String text) async {}

  @override
  PackSink partSink(String fileName) => _no();

  @override
  Future<String> partSha256(String fileName) async => _no();

  @override
  Future<void> install(String fileName) async => _no();

  @override
  Future<void> delete(String fileName) async {}

  @override
  Future<bool> exists(String fileName) async => false;

  @override
  Future<int> usedBytes() async => 0;

  @override
  Future<int?> freeBytes() async => null;

  @override
  Future<String> installStyleAssets(AssetBundle bundle, {required String version}) async => _no();
}

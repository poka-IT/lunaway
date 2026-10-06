import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _log = Logger('offline');

/// Android and iOS keep packs; macOS and Windows draw their map in a web
/// view that reads no local file, so they keep none.
PackFiles platformPackFiles() =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS
    ? IoPackFiles()
    : const _DesktopPackFiles();

/// The packs in the application support folder: not a cache the system may
/// empty when space runs short (a traveller counts on them where there is
/// no network), and out of the backups (Android's rules back up the user
/// database alone; on iOS the folder is marked excluded).
final class IoPackFiles implements PackFiles {
  new({Future<Directory> Function()? root}) : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;
  Future<String>? _dir;

  static const _channel = MethodChannel('lunaway/files');

  @override
  bool get supported => true;

  @override
  Future<String> directory() => _dir ??= () async {
    final dir = Directory(p.join((await _root()).path, 'offline_maps'));
    await dir.create(recursive: true);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await _channel.invokeMethod<bool>('excludeFromBackup', dir.path);
      } on Object catch (e) {
        _log.warning('could not keep the offline maps out of the backups: $e');
      }
    }
    return dir.path;
  }();

  /// [name] in the packs' folder; a name that would leave it is refused
  /// (the names are checked when read, this holds whatever comes).
  Future<File> _file(String name) async {
    final dir = await directory();
    final path = p.join(dir, name);
    if (!p.isWithin(dir, path)) throw ArgumentError.value(name, 'name', 'outside the packs');
    return File(path);
  }

  @override
  Future<String?> readIndex() async {
    final f = await _file('index.json');
    return f.existsSync() ? await f.readAsString() : null;
  }

  @override
  Future<void> writeIndex(String json) async {
    // A new file renamed over the old one: an index cut halfway by the end
    // of the app never replaces a good one.
    final f = await _file('index.json.new');
    await f.writeAsString(json, flush: true);
    await f.rename((await _file('index.json')).path);
  }

  @override
  Future<String?> readManifestCopy() async {
    final f = await _file('manifest.json');
    return f.existsSync() ? await f.readAsString() : null;
  }

  @override
  Future<void> writeManifestCopy(String text) async {
    await (await _file('manifest.json')).writeAsString(text, flush: true);
  }

  @override
  PackSink partSink(String fileName) => _FileSink(() => _file('$fileName.part'));

  @override
  Future<String> partSha256(String fileName) async {
    final path = (await _file('$fileName.part')).path;
    return await Isolate.run(() => _sha256Of(path));
  }

  @override
  Future<void> install(String fileName) async {
    final part = await _file('$fileName.part');
    await part.rename((await _file(fileName)).path);
  }

  @override
  Future<void> delete(String fileName) async {
    for (final name in [fileName, '$fileName.part']) {
      final f = await _file(name);
      if (f.existsSync()) await f.delete();
    }
  }

  @override
  Future<bool> exists(String fileName) async => (await _file(fileName)).existsSync();

  @override
  Future<int?> freeBytes() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    try {
      return await _channel.invokeMethod<int>('freeBytes', await directory());
    } on Object catch (e) {
      _log.warning('free room of the device unknown: $e');
      return null;
    }
  }

  @override
  Future<int> usedBytes() async {
    var total = 0;
    await for (final e in Directory(await directory()).list()) {
      if (e is File && (e.path.endsWith('.pmtiles') || e.path.endsWith('.part'))) {
        total += e.lengthSync();
      }
    }
    return total;
  }

  @override
  Future<String> installStyleAssets(AssetBundle bundle, {required String version}) async {
    final root = Directory(p.join(await directory(), 'style'));
    final marker = File(p.join(root.path, '.version'));
    if (marker.existsSync() && await marker.readAsString() == version) return root.path;
    const prefix = 'assets/map/offline/';
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith(prefix) || asset.endsWith('regions.json')) continue;
      final out = File(p.join(root.path, asset.substring(prefix.length)));
      await out.parent.create(recursive: true);
      final data = await bundle.load(asset);
      await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    await marker.writeAsString(version, flush: true);
    return root.path;
  }
}

String _sha256Of(String path) {
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(1 << 20);
    while (true) {
      final n = file.readIntoSync(buffer);
      if (n <= 0) break;
      input.add(Uint8List.sublistView(buffer, 0, n));
    }
  } finally {
    file.closeSync();
  }
  input.close();
  return out.value.toString();
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// The part of a pack: appended to as bytes arrive, flushed at the end of
/// each attempt.
final class _FileSink implements PackSink {
  new(this._path);

  final Future<File> Function() _path;
  RandomAccessFile? _open;

  Future<RandomAccessFile> _raf() async =>
      _open ??= await (await _path()).open(mode: FileMode.append);

  @override
  Future<int> length() async {
    final f = await _path();
    return f.existsSync() ? f.lengthSync() : 0;
  }

  @override
  Future<void> truncate() async {
    final raf = await _raf();
    await raf.truncate(0);
    await raf.setPosition(0);
  }

  @override
  Future<void> append(List<int> bytes) async {
    await (await _raf()).writeFrom(bytes);
  }

  @override
  Future<void> close() async {
    final raf = _open;
    _open = null;
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

/// macOS and Windows: no offline map (see [platformPackFiles]).
final class _DesktopPackFiles implements PackFiles {
  const new();

  @override
  bool get supported => false;

  Never _no() => throw UnsupportedError('no offline maps on this platform');

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

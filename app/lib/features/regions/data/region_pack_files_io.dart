import 'dart:io';
import 'dart:isolate';

import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/offline/data/pack_files_io.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:path/path.dart' as p;

RegionPackFiles platformRegionPackFiles() => IoRegionPackFiles();

/// Packs in a folder beside the place cache, so they share its place out of
/// the backups (`CacheDatabase.directory`).
final class IoRegionPackFiles implements RegionPackFiles {
  new({Future<Directory> Function()? root}) : _root = root ?? CacheDatabase.directory;

  final Future<Directory> Function() _root;

  Future<Directory> _dir() async {
    final dir = Directory(p.join((await _root()).path, 'region_packs'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  bool get supported => true;

  @override
  Future<String> fetch(
    RegionPack pack,
    Uri url, {
    required PackDownloader downloader,
    void Function(int received)? onProgress,
  }) async {
    final name = url.pathSegments.last;
    if (!packFileName.hasMatch(name)) {
      throw const PackDownloadException(PackDownloadFailure.server, 'not a pack file name');
    }
    final dir = await _dir();
    final part = File(p.join(dir.path, '$name.part'));
    final result = await downloader.download(
      url,
      size: pack.bytes,
      sink: FilePackSink(() async => part),
      token: PackDownloadToken(),
      onProgress: onProgress,
    );
    if (!result.complete) {
      throw const PackDownloadException(PackDownloadFailure.network, 'stopped before its end');
    }
    final raw = p.join(dir.path, name.replaceAll(RegExp(r'\.gz$'), ''));
    final partPath = part.path;
    final failure = await Isolate.run(
      () => _checkAndInflate(partPath, raw, sha256: pack.sha256, rawBytes: pack.rawBytes),
    );
    if (failure != null) {
      // A file that is not the one the manifest describes is never
      // resumed: the next attempt starts over.
      if (part.existsSync()) await part.delete();
      final out = File(raw);
      if (out.existsSync()) await out.delete();
      throw PackDownloadException(PackDownloadFailure.corrupt, failure);
    }
    return raw;
  }

  @override
  Future<void> release(String path) async {
    final dir = await _dir();
    for (final f in [File(path), File('$path.gz.part')]) {
      if (p.isWithin(dir.path, f.path) && f.existsSync()) await f.delete();
    }
  }

  @override
  Future<int> usedBytes() async {
    var total = 0;
    await for (final e in (await _dir()).list()) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }
}

/// Checks the download at [part] against the manifest's [sha256], then
/// writes it decompressed to [raw] and checks its size; null when both
/// hold, else why not. Runs in an isolate: a country's pack is megabytes.
Future<String?> _checkAndInflate(
  String part,
  String raw, {
  required String sha256,
  required int rawBytes,
}) async {
  if (sha256OfFile(part) != sha256) return 'SHA-256 of the download differs from the manifest';
  final out = File(raw);
  await File(part).openRead().transform(gzip.decoder).pipe(out.openWrite());
  final length = out.lengthSync();
  if (length != rawBytes) return 'decompressed to $length bytes, the manifest says $rawBytes';
  return null;
}

import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/regions/data/region_pack_files.dart';
import 'package:lunaway/features/regions/domain/regions.dart';

/// The web syncs a region from the feed: its SQLite (WebAssembly) can
/// attach a file only once it is in its virtual file system.
RegionPackFiles platformRegionPackFiles() => const _NoRegionPackFiles();

final class _NoRegionPackFiles implements RegionPackFiles {
  const new();

  @override
  bool get supported => false;

  @override
  Future<String> fetch(
    RegionPack pack,
    Uri url, {
    required PackDownloader downloader,
    void Function(int received)? onProgress,
  }) async => throw UnsupportedError('no region packs on the web');

  @override
  Future<void> release(String path) async {}

  @override
  Future<int> usedBytes() async => 0;
}

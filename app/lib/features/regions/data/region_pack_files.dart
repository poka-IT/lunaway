import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/features/offline/data/pack_download.dart';
import 'package:lunaway/features/regions/data/region_pack_files_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/regions/data/region_pack_files_web.dart'
    as platform;
import 'package:lunaway/features/regions/domain/regions.dart';

/// The first-sync packs of the places on the device: downloaded beside the
/// place cache (out of the backups like it), checked, decompressed, then
/// imported and removed. Every native platform; the web's SQLite cannot
/// attach a file, so it syncs a region from the feed instead
/// (docs/region-packs.md, "Importing it").
abstract interface class RegionPackFiles {
  /// The platform's own, or a stand-in that keeps nothing on the web.
  factory platformFiles() => platform.platformRegionPackFiles();

  /// Whether this platform imports packs.
  bool get supported;

  /// Downloads [pack] from [url] with [downloader], resuming a part an
  /// earlier attempt left; checks its size and SHA-256 against the
  /// manifest; decompresses it. Answers the path of the SQLite file, which
  /// [release] removes once imported. Throws a [PackDownloadException].
  Future<String> fetch(
    RegionPack pack,
    Uri url, {
    required PackDownloader downloader,
    void Function(int received)? onProgress,
  });

  /// Removes the decompressed file at [path] and the download it came
  /// from.
  Future<void> release(String path);

  /// Bytes taken by downloads not imported yet.
  Future<int> usedBytes();
}

/// The address of a pack named by the manifest: a relative URL resolved on
/// the API, or an absolute one on the API's host or the public API, under
/// `/packs/places/`, with the file name the server gives packs. Null for
/// anything else: the region then syncs from the feed, and the app never
/// fetches from a host the manifest would name.
Uri? placesPackUrl(AppConfig config, String url) {
  final base = config.apiBase;
  final parsed = Uri.tryParse(url);
  if (parsed == null) return null;
  final resolved = parsed.hasScheme ? parsed : base.resolveUri(parsed);
  final ours =
      resolved.userInfo.isEmpty &&
      ((resolved.scheme == base.scheme &&
              resolved.host == base.host &&
              resolved.port == base.port) ||
          (resolved.scheme == 'https' &&
              resolved.host == Uri.parse(AppConfig.publicApi).host &&
              resolved.port == 443));
  final segments = resolved.pathSegments;
  if (!ours ||
      resolved.hasQuery ||
      resolved.hasFragment ||
      segments.length < 3 ||
      segments[segments.length - 3] != 'packs' ||
      segments[segments.length - 2] != 'places' ||
      !packFileName.hasMatch(segments.last)) {
    return null;
  }
  return resolved;
}

/// The name of a pack file (`FR-BRE-1234-0123456789ab.sqlite.gz`).
final packFileName = RegExp(r'^[A-Z0-9-]+-[0-9]+-[0-9a-f]{12}\.sqlite\.gz$');

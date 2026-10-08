import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/offline/domain/packs.dart';
import 'package:meta/meta.dart';

/// The pack to download first for a region (`RegionPack` of the API,
/// docs/region-packs.md): an SQLite file compressed with gzip, served under
/// a name that never changes content.
@immutable
final class RegionPack {
  const new({
    required this.url,
    required this.format,
    required this.bytes,
    required this.rawBytes,
    required this.sha256,
    required this.version,
    required this.cursor,
    required this.places,
    required this.bounds,
    required this.generatedAt,
  });

  /// The only format this app imports; a pack of another is skipped and
  /// the region syncs from the feed instead.
  static const supportedFormat = 'sqlite-gzip-1';

  final String url;
  final String format;

  /// Its size as downloaded.
  final int bytes;

  /// Its size once decompressed.
  final int rawBytes;

  /// Lowercase hexadecimal SHA-256 of the file as downloaded.
  final String sha256;

  /// Changes with every new pack of the region.
  final String version;

  /// The `since` that continues the feed after the pack.
  final String cursor;
  final int places;
  final GeoBounds bounds;
  final DateTime generatedAt;

  bool get importable => format == supportedFormat;

  @override
  bool operator ==(Object other) =>
      other is RegionPack && other.url == url && other.version == version;

  @override
  int get hashCode => Object.hash(url, version);
}

/// A region a device can keep offline: one of the thirteen regions of
/// metropolitan France (`FR-BRE`), the few French places outside every
/// commune (`FR`), or a country elsewhere (`ES`).
@immutable
final class RegionInfo {
  const new({
    required this.code,
    required this.country,
    required this.name,
    required this.nameFr,
    this.pack,
  });

  final String code;

  /// ISO 3166-1 alpha-2.
  final String country;

  /// Its name in English and in French.
  final String name;
  final String nameFr;

  /// Null while the server built none: the region then syncs from the feed.
  final RegionPack? pack;

  /// Its name in [language]; English for any language but French.
  String nameIn(String language) => language == 'fr' ? nameFr : name;

  /// A French region, of the thirteen.
  bool get frenchRegion => code.startsWith('FR-');

  @override
  bool operator ==(Object other) => other is RegionInfo && other.code == code && other.pack == pack;

  @override
  int get hashCode => Object.hash(code, pack);
}

/// The regions the server offers (`Query.regions`).
@immutable
final class RegionCatalog {
  const new(this.regions, {this.fromCopy = false});

  final List<RegionInfo> regions;

  /// A copy kept from an earlier read: the network did not answer now.
  final bool fromCopy;

  RegionInfo? byCode(String code) => regions.firstWhereOrNull((r) => r.code == code);

  /// France as one choice: its thirteen regions and the places outside
  /// every commune.
  Set<String> get france => {
    for (final r in regions)
      if (r.country == 'FR') r.code,
  };

  /// The download of [codes], in bytes: the packs the server built.
  int bytesOf(Iterable<String> codes) =>
      codes.map(byCode).nonNulls.map((r) => r.pack?.bytes ?? 0).sum;

  /// The regions as the picker lists them: France first (its regions under
  /// it), then the other countries, each list in the order of [sortName]
  /// (the name the reader sees, as an index sorts it).
  List<RegionGroup> groups(String Function(RegionInfo) sortName) {
    int byName(RegionInfo a, RegionInfo b) => sortName(a).compareTo(sortName(b));
    final french = [
      for (final r in regions)
        if (r.frenchRegion) r,
    ]..sort(byName);
    final others = [
      for (final r in regions)
        if (r.country != 'FR') r,
    ]..sort(byName);
    return [
      if (french.isNotEmpty) RegionGroup(country: 'FR', regions: french, codes: france),
      for (final r in others) RegionGroup(country: r.country, regions: [r], codes: {r.code}),
    ];
  }

  /// The sync region at [point], read from the outlines of the offline
  /// maps (`assets/map/offline/regions.json`, whose ids are the codes in
  /// lower case); null at sea, overseas or in a country the server does
  /// not cover. The outlines are simplified: near a border the answer may
  /// be the neighbour, which the user then corrects in the picker.
  String? regionAt(LatLng point, PackOutlines outlines) {
    for (final id in outlines.ids) {
      if (!outlines.covers(id, _world, point)) continue;
      final code = attachedRegions[id.toUpperCase()] ?? id.toUpperCase();
      if (byCode(code) != null) return code;
    }
    return null;
  }

  static const _world = GeoBounds(south: -90, west: -180, north: 90, east: 180);

  /// What a device keeps before the user chooses: the region where the
  /// user is ([here]), alone, or nothing when [here] is not a region of the
  /// manifest. All of France weighed 24.4 MB on 2026-10-08, once the
  /// external community source came in, against 0.3 to 4.1 MB for one of
  /// its regions: it stays one choice away in the offline maps, with its
  /// size. `FR`, the few French places outside every commune, is never a
  /// choice of its own.
  Set<String> firstChoice(String? here) {
    final code = here == null ? null : byCode(here)?.code;
    return code == null || code == 'FR' ? const {} : {code};
  }
}

/// The zoom from which the map's view names one region: below it, a view
/// of France shows several and the region at its centre says nothing of
/// the user.
const regionalZoom = 6.5;

/// The microstates that sync with the region around them
/// (`lunaway_domain::region::ATTACHED`).
const attachedRegions = {
  'MC': 'FR-PAC',
  'AD': 'ES',
  'GI': 'ES',
  'SM': 'IT',
  'VA': 'IT',
  'LI': 'CH',
  'SJ': 'NO',
  'AX': 'FI',
};

/// One line of the picker: a country, with its regions when it has
/// several (France).
@immutable
final class RegionGroup {
  const new({required this.country, required this.regions, required this.codes});

  final String country;

  /// The regions listed under it; one for a country synced whole.
  final List<RegionInfo> regions;

  /// Every code the country stands for (France's thirteen regions and
  /// `FR`).
  final Set<String> codes;

  bool get split => regions.length > 1;
}

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:meta/meta.dart';

/// The manifest of the offline packs (`/packs/manifest.json` on the tile
/// host, docs/deploy.md "Offline packs"): one PMTiles extract of the
/// basemap per region or country, zoom 0 to 14.
@immutable
final class PackManifest {
  const new({required this.build, required this.packs, this.attribution = '© OpenStreetMap'});

  /// Reads [text]; throws a [FormatException] for anything but a version 1
  /// manifest. A pack that lacks a field it needs, or whose file name could
  /// leave the manifest's folder, is left out.
  factory parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw const FormatException('not a manifest');
    if (json['version'] != supportedVersion) {
      throw FormatException('manifest version ${json['version']}');
    }
    final build = json['build'];
    final packs = json['packs'];
    if (build is! String || packs is! List<dynamic>) throw const FormatException('no packs');
    return PackManifest(
      build: build,
      attribution: json['attribution'] as String? ?? '© OpenStreetMap',
      packs: [for (final p in packs) ?PackInfo.fromJson(p)],
    );
  }

  /// The only format this app reads; another is refused rather than
  /// misread.
  static const supportedVersion = 1;

  /// The planet build of the set, the date of its OpenStreetMap data.
  final String build;
  final List<PackInfo> packs;
  final String attribution;

  PackInfo? byId(String id) => packs.firstWhereOrNull((p) => p.id == id);
}

/// What a pack covers.
enum PackGroup {
  /// The 13 regions of metropolitan France.
  france,

  /// The 5 overseas regions.
  overseas,

  /// Countries.
  countries,
}

/// One pack of the manifest.
@immutable
final class PackInfo {
  const new({
    required this.id,
    required this.names,
    required this.country,
    required this.bounds,
    required this.url,
    required this.size,
    required this.sha256,
    required this.build,
    this.region = true,
    this.maxZoom = 14,
  });

  static PackInfo? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final url = json['url'];
    final size = json['size'];
    final sha = json['sha256'];
    final build = json['build'];
    final bbox = json['bbox'];
    final names = json['name'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9-]{2,12}$').hasMatch(id) ||
        url is! String ||
        !safeFileName(url) ||
        size is! int ||
        size <= 0 ||
        size > maxPackBytes ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        build is! String ||
        !_buildPattern.hasMatch(build) ||
        bbox is! List<dynamic> ||
        bbox.length != 4 ||
        bbox.any((v) => v is! num)) {
      return null;
    }
    final b = [for (final v in bbox) (v as num).toDouble()];
    return PackInfo(
      id: id,
      names: {
        if (names is Map<String, dynamic>)
          for (final MapEntry(:key, :value) in names.entries)
            if (value is String) key: value,
      },
      country: json['country'] as String? ?? id,
      bounds: GeoBounds(west: b[0], south: b[1], east: b[2], north: b[3]),
      url: url,
      size: size,
      sha256: sha,
      build: build,
      region: json['kind'] == 'region',
      maxZoom: (json['max_zoom'] as num?)?.toInt() ?? 14,
    );
  }

  /// ISO 3166-1 alpha-2 for a country, ISO 3166-2 for a French region.
  final String id;
  final Map<String, String> names;
  final String country;
  final GeoBounds bounds;

  /// The file name, relative to the manifest's URL.
  final String url;
  final int size;
  final String sha256;
  final String build;
  final bool region;
  final int maxZoom;

  String name(String language) => names[language] ?? names['en'] ?? names.values.firstOrNull ?? id;

  /// French regions keep their own group, overseas apart.
  PackGroup get group {
    if (!region || country != 'fr') return PackGroup.countries;
    return RegExp(r'^fr-97\d$').hasMatch(id) ? PackGroup.overseas : PackGroup.france;
  }

  /// The file this pack is kept in on the device: one per id and build.
  String get fileName => '$id-$build.pmtiles';
}

/// The build of a pack, the date of its data (`20261005`): with the id, it
/// names the file on the device, so nothing else may stand there.
final _buildPattern = RegExp(r'^\d{8}$');

/// The largest pack a manifest may announce: past it, a mistake or a
/// hostile manifest, never a region.
const int maxPackBytes = 8 * 1024 * 1024 * 1024;

/// A name the manifest may give a pack's file: a plain file name, so a
/// manifest cannot make the app read or write outside its folder.
bool safeFileName(String name) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.pmtiles$').hasMatch(name) && !name.contains('..');

/// A pack on the device, checked against its manifest entry.
@immutable
final class InstalledPack {
  const new({
    required this.id,
    required this.build,
    required this.size,
    required this.sha256,
    required this.names,
    required this.bounds,
    required this.installedAt,
    this.maxZoom = 14,
  });

  factory from(PackInfo info, DateTime at) => InstalledPack(
    id: info.id,
    build: info.build,
    size: info.size,
    sha256: info.sha256,
    names: info.names,
    bounds: info.bounds,
    installedAt: at,
    maxZoom: info.maxZoom,
  );

  static InstalledPack? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final build = json['build'];
    final size = json['size'];
    final sha = json['sha256'];
    final bbox = json['bbox'];
    final at = DateTime.tryParse('${json['installedAt']}');
    if (id is! String ||
        !RegExp(r'^[a-z0-9-]{2,12}$').hasMatch(id) ||
        build is! String ||
        !_buildPattern.hasMatch(build) ||
        size is! int ||
        sha is! String ||
        at == null ||
        bbox is! List<dynamic> ||
        bbox.length != 4) {
      return null;
    }
    final b = [for (final v in bbox) (v as num).toDouble()];
    final names = json['names'];
    return InstalledPack(
      id: id,
      build: build,
      size: size,
      sha256: sha,
      names: {
        if (names is Map<String, dynamic>)
          for (final MapEntry(:key, :value) in names.entries)
            if (value is String) key: value,
      },
      bounds: GeoBounds(west: b[0], south: b[1], east: b[2], north: b[3]),
      installedAt: at.toUtc(),
      maxZoom: (json['maxZoom'] as num?)?.toInt() ?? 14,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'build': build,
    'size': size,
    'sha256': sha256,
    'names': names,
    'bbox': [bounds.west, bounds.south, bounds.east, bounds.north],
    'installedAt': installedAt.toUtc().toIso8601String(),
    'maxZoom': maxZoom,
  };

  final String id;
  final String build;
  final int size;
  final String sha256;
  final Map<String, String> names;
  final GeoBounds bounds;
  final DateTime installedAt;
  final int maxZoom;

  String name(String language) => names[language] ?? names['en'] ?? id;

  String get fileName => '$id-$build.pmtiles';

  /// The date of its OpenStreetMap data, from the build (`20261005`).
  DateTime? get dataDate => buildDate(build);

  @override
  bool operator ==(Object other) =>
      other is InstalledPack && other.id == id && other.build == build && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(id, build, sha256);
}

/// The day of a build name (`20261005`); null for another form.
DateTime? buildDate(String build) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(build);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// The outlines of the packs (`assets/map/offline/regions.json`, from
/// `infra/tiles/packs/regions.geojson`): which pack covers a point. A pack
/// without an outline here is read by its box.
@immutable
final class PackOutlines {
  const new(this._rings);

  factory parse(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return PackOutlines({
      for (final MapEntry(:key, :value) in json.entries)
        key: [
          for (final ring in value as List<dynamic>)
            [
              for (final p in ring as List<dynamic>)
                (((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble()),
            ],
        ],
    });
  }

  static const empty = PackOutlines({});

  final Map<String, List<List<(double, double)>>> _rings;

  /// Whether the pack [id] with box [bounds] covers [point].
  bool covers(String id, GeoBounds bounds, LatLng point) {
    if (!bounds.contains(point)) return false;
    final rings = _rings[id];
    if (rings == null) return true;
    return rings.any((ring) => _inside(ring, point.lon, point.lat));
  }

  /// Even-odd ray casting.
  static bool _inside(List<(double, double)> ring, double x, double y) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final (xi, yi) = ring[i];
      final (xj, yj) = ring[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }
}

/// The smallest of [packs] that covers [point] (a region before its
/// country), or null.
T? packAt<T>(
  Iterable<T> packs,
  LatLng point, {
  required PackOutlines outlines,
  required String Function(T) id,
  required GeoBounds Function(T) bounds,
}) {
  double area(GeoBounds b) => (b.north - b.south) * (b.east - b.west);
  final covering = [
    for (final p in packs)
      if (outlines.covers(id(p), bounds(p), point)) p,
  ]..sort((a, b) => area(bounds(a)).compareTo(area(bounds(b))));
  return covering.firstOrNull;
}

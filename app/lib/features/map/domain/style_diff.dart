import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// What turns a loaded basemap style into another without loading it: the
/// paint properties that differ, layer by layer, and the sprite sheet when
/// it changes. Aube and Minuit share their sources, their layers and their
/// layout and differ only there (`tool/map_style/`), so the theme turns
/// at the next frame instead of reloading every tile and image of the map.
@immutable
final class StyleDiff {
  const new({required this.paint, this.spriteFrom, this.spriteTo});

  /// The paint properties to set, by layer id, with their new values (null
  /// for a property the new style leaves at its default).
  final Map<String, Map<String, Object?>> paint;

  /// The sprite sheets before and after, when they differ.
  final String? spriteFrom;
  final String? spriteTo;

  bool get changesSprite => spriteTo != null && spriteTo != spriteFrom;

  bool get isEmpty => paint.isEmpty && !changesSprite;

  /// The difference from [from] to [to], two style documents (JSON text);
  /// null when it is more than paint and sprite (another source, layer,
  /// layout, filter or glyph server), or when either is no document (a
  /// style URL): the map loads [to] whole.
  static StyleDiff? between(String from, String to) {
    final a = _document(from);
    final b = _document(to);
    if (a == null || b == null) return null;
    const equal = DeepCollectionEquality();
    for (final key in {...a.keys, ...b.keys}) {
      if (key == 'layers' || key == 'sprite' || key == 'name' || key == 'metadata') continue;
      if (!equal.equals(a[key], b[key])) return null;
    }
    final layersA = a['layers'];
    final layersB = b['layers'];
    if (layersA is! List || layersB is! List || layersA.length != layersB.length) return null;
    final paint = <String, Map<String, Object?>>{};
    for (var i = 0; i < layersA.length; i++) {
      final la = layersA[i];
      final lb = layersB[i];
      if (la is! Map || lb is! Map) return null;
      for (final key in {...la.keys, ...lb.keys}) {
        if (key == 'paint' || key == 'metadata') continue;
        if (!equal.equals(la[key], lb[key])) return null;
      }
      final pa = la['paint'] is Map ? la['paint'] as Map : const <Object?, Object?>{};
      final pb = lb['paint'] is Map ? lb['paint'] as Map : const <Object?, Object?>{};
      final changed = <String, Object?>{
        for (final p in {...pa.keys, ...pb.keys})
          if (!equal.equals(pa[p], pb[p])) '$p': pb[p],
      };
      if (changed.isNotEmpty) paint[la['id'] as String] = changed;
    }
    final spriteA = a['sprite'];
    final spriteB = b['sprite'];
    if ((spriteA != null && spriteA is! String) || (spriteB != null && spriteB is! String)) {
      return null;
    }
    return StyleDiff(paint: paint, spriteFrom: spriteA as String?, spriteTo: spriteB as String?);
  }

  static Map<String, Object?>? _document(String style) {
    if (!style.trimLeft().startsWith('{')) return null;
    try {
      return jsonDecode(style) as Map<String, Object?>;
    } on FormatException {
      return null;
    }
  }
}

import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// Changes to a layer's properties that leave the others as they are.
///
/// maplibre_gl 0.27.1 sends every property its typed classes know
/// (`SymbolLayerProperties` and the like) to `setLayerProperties`, the
/// unset ones as null (`toJson(skipNulls: false)`), and a null resets a
/// property to the style's default on Android, iOS and the web: a change of
/// the price under the route map's pins took their image, their size, their
/// anchor and their text's font with it. Every change goes through
/// [updateLayerProperties] (gate: `structure_check` rule
/// `layer-properties`).
extension LayerPropertyUpdates on gl.MapLibreMapController {
  /// Sets the [properties] of the layer [layerId] named there, as a style
  /// document writes them (`'text-color': '#123456'`), and only those. A
  /// null given here resets that property.
  Future<void> updateLayerProperties(String layerId, Map<String, Object?> properties) =>
      setLayerProperties(layerId, _NamedProperties(properties));
}

/// [properties] as they are: the plugin's `toJson` adds no key to them.
final class _NamedProperties implements gl.LayerProperties {
  const new(this.properties);

  final Map<String, Object?> properties;

  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) => {
    for (final MapEntry(:key, :value) in properties.entries)
      if (value != null || !skipNulls) key: value,
  };
}

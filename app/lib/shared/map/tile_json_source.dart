import 'package:maplibre_gl/maplibre_gl.dart' as gl;

/// A vector source named by its TileJSON (`/places/tiles.json`,
/// `/poi/tiles.json`), which alone says the zooms its tiles exist at and
/// the area they cover. The plugin's constructor fills in zooms 0 to 22 and
/// the whole world, and MapLibre GL JS prefers a source's own values to its
/// TileJSON's: the browser asked for tiles above zoom 14, which the API does
/// not serve, instead of drawing those of zoom 14 larger, and the places and
/// the points left the map from zoom 15. The native plugins read the URL
/// alone. `test/contract/tile_sources_contract_test.dart` holds both
/// sources to the TileJSON the API serves (`schema/tilejson.json`).
gl.VectorSourceProperties tileJsonSource(String url) =>
    gl.VectorSourceProperties(url: url, minzoom: null, maxzoom: null, bounds: null);

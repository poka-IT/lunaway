import 'package:flutter/foundation.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

/// What the map draws of the points of interest, given to both map engines
/// with the rest of the map's data. Null hides the layer.
@immutable
final class PoiLayerView {
  const new({
    required this.tileJsonUrl,
    this.category,
    this.openNowOnly = false,
    this.state = PoiLayerState.empty,
    this.night = false,
    this.selected,
    this.fuelLabels = const [],
  });

  /// The TileJSON of the layer (`/poi/tiles.json` on the API).
  final String tileJsonUrl;

  /// The chip turned on; null shows every point quietly at street zoom.
  final PoiCategory? category;
  final bool openNowOnly;
  final PoiLayerState state;

  /// At night what is open around the clock is drawn first.
  final bool night;

  /// The point whose page is open, drawn large on top.
  final PoiFeature? selected;

  /// The price of the chosen fuel under each station in view, while the
  /// fuel chip is on.
  final List<FuelLabel> fuelLabels;

  @override
  bool operator ==(Object other) =>
      other is PoiLayerView &&
      other.tileJsonUrl == tileJsonUrl &&
      other.category == category &&
      other.openNowOnly == openNowOnly &&
      other.state == state &&
      other.night == night &&
      other.selected == selected &&
      other.selected?.kind == selected?.kind &&
      listEquals(other.fuelLabels, fuelLabels);

  @override
  int get hashCode => Object.hash(tileJsonUrl, category, openNowOnly, state, night, selected);
}

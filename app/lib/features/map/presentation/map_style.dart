/// The ids and filters of the layers Lunaway adds on top of the basemap,
/// shared by both map engines. How they look is in `shared/theme/map_look.dart`,
/// the pins themselves in `shared/map/pin_painter.dart`.
abstract final class MapStyle {
  static const placesSource = 'lw-places';
  static const selectionSource = 'lw-selection';

  static const clustersLayer = 'lw-clusters';
  static const clusterCountLayer = 'lw-cluster-count';
  static const placesLayer = 'lw-places';
  static const selectionPinLayer = 'lw-selection-pin';

  /// Topmost first: a tap picks the first layer that has a feature there.
  static const List<String> tappableLayers = [selectionPinLayer, placesLayer, clustersLayer];

  /// Pins merge into clusters below this zoom; past it every pin shows.
  static const clusterMaxZoom = 12.0;
  static const clusterRadius = 56.0;

  static const List<Object> clusterFilter = ['has', 'point_count'];
  static const List<Object> pointFilter = [
    '!',
    ['has', 'point_count'],
  ];
}

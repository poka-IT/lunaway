import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The display name of a source: the name the API gives it in the place's
/// source list, else a name for the well-known ones, else its id. Source
/// names are brand names, translated only where the source has none.
String sourceName(Translations t, String sourceId, {List<PlaceSource> sources = const []}) {
  for (final s in sources) {
    if (s.source.id == sourceId) return s.source.name;
  }
  return switch (sourceId) {
    'osm' => 'OpenStreetMap',
    'atout-france' => 'Atout France',
    'community' => t.appTitle,
    _ => sourceId,
  };
}

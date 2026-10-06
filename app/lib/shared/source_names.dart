import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
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
    'prix-carburants' => t.poi.fuelPrices,
    'laposte' => 'La Poste',
    'finess' => 'FINESS',
    _ when isLunawayCommunity(sourceId) => t.appTitle,
    _ => sourceId,
  };
}

/// What a badge says of an item of [sourceId]: its source's name, and its
/// licence for the reviews, ratings and photos Lunaway users publish under
/// CC BY 4.0, which differs from the places' ODbL.
String itemSourceLabel(Translations t, String sourceId, {List<PlaceSource> sources = const []}) {
  final name = sourceName(t, sourceId, sources: sources);
  if (sourceId != communityCcBySourceId) return name;
  return t.place.sourceWithLicence(source: name, licence: t.place.licenceCcBy);
}

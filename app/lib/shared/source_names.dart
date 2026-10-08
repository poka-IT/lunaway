import 'package:intl/intl.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// The display name of a source: the name the API gives it in the place's
/// source list, else a name for the well-known ones, else its id. Source
/// names are brand names, translated only where the source has none.
String sourceName(Translations t, String sourceId, {List<PlaceSource> sources = const []}) {
  // The wording the agreement sets, in the reader's language, whatever
  // name the API gives it: never the partner's own name.
  if (sourceId == extcomSourceId) return t.sources.extcom.label;
  for (final s in sources) {
    if (s.source.id == sourceId) return s.source.name;
  }
  return switch (sourceId) {
    'osm' => 'OpenStreetMap',
    'atout-france' => 'Atout France',
    'prix-carburants' => t.poi.fuelPrices,
    'laposte' => 'La Poste',
    'finess' => 'FINESS',
    'wikimedia-commons' => 'Wikimedia Commons',
    'wikidata' => 'Wikidata',
    'wikipedia' => 'Wikipedia',
    'panoramax' => 'Panoramax',
    'datatourisme' => 'DATAtourisme',
    'mangrove' => 'Mangrove Reviews',
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

/// What a photo's badge says: its source, what it shows when it is not the
/// place itself (a street view, the surroundings), and for a photo of
/// another source its author too, the credit that source's photos are
/// shown under.
String photoCredit(Translations t, Photo photo, {List<PlaceSource> sources = const []}) {
  var label = itemSourceLabel(t, photo.sourceId, sources: sources);
  final kind = photoKindLabel(t, photo.kind);
  if (kind != null) label = t.place.photoCredit(source: label, author: kind);
  final author = photo.authorName;
  if (author == null || isLunawayCommunity(photo.sourceId)) return label;
  return t.place.photoCredit(source: label, author: author);
}

/// What a photo of another source shows, when it is not the place itself.
String? photoKindLabel(Translations t, PhotoKind? kind) => switch (kind) {
  PhotoKind.streetView => t.place.photoStreetView,
  PhotoKind.surroundings => t.place.photoSurroundings,
  PhotoKind.place || null => null,
};

/// The terms of an item of another source on one line: its licence, who
/// published it and the date of its last update, as the licences ask.
String? termsLine(Translations t, ItemTerms? terms) {
  if (terms == null) return null;
  final updated = terms.updatedOn;
  final parts = [
    // The partner's items carry the reference of the agreement, which
    // means nothing to a reader: a licence shows only with its text.
    if (terms.licenceUrl != null) ?terms.licence,
    ?terms.publisher,
    if (updated != null)
      t.place.updatedOn(date: DateFormat.yMMMd(t.$meta.locale.languageCode).format(updated)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

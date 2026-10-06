import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// Synthetic places for the demo mode and the tests: real towns, invented
/// spots. Every name ends with "(démo)" so no one mistakes them for real
/// places, and the generator is seeded so every run (and every golden image)
/// sees the same data. Opening intervals are computed from [now] the way the
/// server computes them at sync time.
List<Place> demoPlaces({int count = 420, int seed = 20261006, DateTime? now}) {
  final rng = _Rng(seed);
  final today = now ?? DateTime.now();
  final places = <Place>[];
  final updated = DateTime.utc(2026, 9, 28, 8);
  for (var i = 0; i < count; i++) {
    final town = _towns[i % _towns.length];
    final kind = _pickKind(rng);
    // Within about 12 km of the town centre.
    final lat = town.lat + (rng.next() - 0.5) * 0.22;
    final lon = town.lon + (rng.next() - 0.5) * 0.3;
    final overnight = _overnight(kind, rng);
    final services = _services(kind, rng);
    final name = '${_prefix(kind)} ${_names[rng.nextInt(_names.length)]} (démo)';
    final confirmedDaysAgo = rng.nextInt(540);
    final hours = rng.next() < 0.55 ? _hours[rng.nextInt(_hours.length)] : null;
    // Most places carry synthetic community content: ratings, descriptions
    // in several languages, photos and reviews, all invented.
    final withCommunity = rng.next() < 0.65;
    final communityRating = withCommunity && rng.next() < 0.9
        ? SourceRating(
            sourceId: demoCommunitySource.id,
            average: 2.6 + rng.nextInt(24) / 10,
            count: 1 + rng.nextInt(240),
          )
        : null;
    final description = rng.next() < 0.7 ? _descriptions[rng.nextInt(_descriptions.length)] : null;
    // The values below draw from the generator in a fixed order, so the
    // demo data stays the same from one version to the next.
    final placeName = kind == PlaceKind.parking && rng.next() < 0.3 ? null : name;
    final activities = {
      for (final a in Activity.values)
        if (rng.next() < 0.12) a,
    };
    final descriptions = [
      if (description != null) ...[
        LocalizedText(
          lang: 'fr',
          text: description.fr,
          sourceId: withCommunity ? demoCommunitySource.id : demoSource.id,
        ),
        if (withCommunity && rng.next() < 0.6)
          LocalizedText(lang: 'en', text: description.en, sourceId: demoCommunitySource.id),
        if (withCommunity && rng.next() < 0.3)
          LocalizedText(lang: 'de', text: description.de, sourceId: demoCommunitySource.id),
      ],
    ];
    final street = rng.next() < 0.6
        ? '${1 + rng.nextInt(40)} ${_streets[rng.nextInt(_streets.length)]}'
        : null;
    final priceParking = _price(kind, rng);
    final priceServices = services.isNotEmpty && rng.next() < 0.3
        ? (2 + rng.nextInt(4)).toDouble()
        : null;
    final maxHeight = kind == PlaceKind.parking && rng.next() < 0.35
        ? const [1.9, 2.0, 2.1, 2.2, 2.5, 3.0][rng.nextInt(6)]
        : (rng.next() < 0.06 ? 3.5 : null);
    final capacity = kind == PlaceKind.nature ? null : 4 + rng.nextInt(60);
    final phone = rng.next() < 0.25
        ? '+33 0 00 00 ${10 + rng.nextInt(89)} ${10 + rng.nextInt(89)}'
        : null;
    final lastConfirmedAt = rng.next() < 0.85
        ? updated.subtract(Duration(days: confirmedDaysAgo))
        : null;
    final updatedAt = updated.subtract(Duration(days: rng.nextInt(30)));
    final sources = [
      PlaceSource(source: demoSource, externalId: 'demo/${i + 1}', fetchedAt: updated),
      if (withCommunity)
        PlaceSource(
          source: demoCommunitySource,
          externalId: 'community-demo/${i + 1}',
          fetchedAt: updated.subtract(const Duration(hours: 5)),
          matchScore: 0.86 + rng.nextInt(14) / 100,
        ),
      if (kind == PlaceKind.campsite && rng.next() < 0.5)
        PlaceSource(
          source: demoRegistrySource,
          externalId: 'registry/${i + 1}',
          fetchedAt: updated.subtract(const Duration(days: 12)),
          matchScore: 0.88 + rng.nextInt(11) / 100,
        ),
    ];
    // The registry classifies the campsites it lists; derived from the
    // index so the generator's sequence above stays as it was.
    final registered = sources.any((s) => s.source.id == demoRegistrySource.id);
    places.add(
      Place(
        id: _demoId(0, i + 1),
        name: placeName,
        kind: kind,
        lat: double.parse(lat.toStringAsFixed(6)),
        lon: double.parse(lon.toStringAsFixed(6)),
        overnight: overnight,
        services: services,
        activities: activities,
        description: description?.fr,
        descriptions: descriptions,
        ratings: [?communityRating],
        address: Address(
          street: street,
          postcode: town.postcode,
          city: town.name,
          countryCode: 'FR',
        ),
        priceParkingEur: priceParking,
        priceServicesEur: priceServices,
        maxHeightM: maxHeight,
        capacity: capacity,
        stars: registered ? 1 + (i * 7) % 5 : null,
        openingHours: hours?.raw,
        openingHoursParsed: hours != null,
        openingIntervals: hours == null ? null : _intervals(hours, today),
        openingValidUntil: hours == null ? null : _windowEnd(today),
        phone: phone,
        lastConfirmedAt: lastConfirmedAt,
        updatedAt: updatedAt,
        sources: sources,
      ),
    );
  }
  return places;
}

/// The source every demo place cites: honest about being invented.
const demoSource = Source(
  id: 'demo',
  name: 'Lunaway demo',
  licence: 'CC0-1.0',
  attribution: 'Synthetic places generated by Lunaway for the demo mode.',
  url: 'https://lunaway.net',
);

/// The source of the synthetic community content: invented ratings,
/// descriptions, photos and reviews, in the shape the server will send for
/// community contributions.
const demoCommunitySource = Source(
  id: communitySourceId,
  name: 'Communauté Lunaway (démo)',
  licence: 'Données de démonstration',
  attribution: 'Notes, descriptions et avis inventés pour la démonstration.',
  url: 'https://lunaway.net',
);

const demoRegistrySource = Source(
  id: 'demo-registry',
  name: 'Demo registry',
  licence: 'CC0-1.0',
  attribution: 'A second synthetic source, to show how sources merge.',
  url: 'https://lunaway.net',
);

/// A small deterministic generator (xorshift32): `dart:math` Random is not
/// guaranteed to give the same sequence on every platform.
final class _Rng {
  new(int seed) : _state = seed == 0 ? 1 : seed & 0xFFFFFFFF;

  int _state;

  int _nextBits() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _state = x & 0xFFFFFFFF;
  }

  /// In [0, 1).
  double next() => _nextBits() / 4294967296;

  int nextInt(int max) => (next() * max).floor();
}

PlaceKind _pickKind(_Rng rng) {
  final r = rng.next();
  if (r < 0.30) return PlaceKind.motorhomeArea;
  if (r < 0.52) return PlaceKind.parking;
  if (r < 0.70) return PlaceKind.campsite;
  if (r < 0.78) return PlaceKind.serviceArea;
  if (r < 0.86) return PlaceKind.nature;
  if (r < 0.90) return PlaceKind.farm;
  if (r < 0.93) return PlaceKind.restArea;
  if (r < 0.95) return PlaceKind.picnicArea;
  if (r < 0.97) return PlaceKind.homestay;
  if (r < 0.985) return PlaceKind.offRoad;
  return PlaceKind.extraService;
}

OvernightStatus _overnight(PlaceKind kind, _Rng rng) {
  final r = rng.next();
  return switch (kind) {
    .motorhomeArea => r < 0.85 ? .allowed : .tolerated,
    .campsite || .farm || .homestay => .allowed,
    .parking =>
      r < 0.45
          ? .tolerated
          : r < 0.75
          ? .dayOnly
          : r < 0.88
          ? .forbidden
          : .unknown,
    .serviceArea || .extraService => r < 0.7 ? .dayOnly : .unknown,
    .nature || .offRoad => r < 0.5 ? .tolerated : .unknown,
    .restArea || .picnicArea => r < 0.4 ? .tolerated : (r < 0.7 ? .dayOnly : .unknown),
  };
}

Set<Service> _services(PlaceKind kind, _Rng rng) {
  double p(Service s) => switch (kind) {
    .motorhomeArea || .serviceArea => switch (s) {
      .drinkingWater || .greyWater || .blackWater => 0.85,
      .wasteBin => 0.6,
      .electricity => 0.45,
      .toilets => 0.3,
      _ => 0.05,
    },
    .campsite || .farm || .homestay => switch (s) {
      .drinkingWater || .toilets || .showers || .electricity => 0.85,
      .greyWater || .blackWater || .wasteBin => 0.6,
      .wifi || .petsAllowed || .laundry => 0.45,
      .swimmingPool => 0.2,
      _ => 0.05,
    },
    _ => switch (s) {
      .wasteBin => 0.3,
      .toilets => 0.15,
      .mobileData => 0.3,
      _ => 0.03,
    },
  };
  return {
    for (final s in Service.values)
      if (rng.next() < p(s)) s,
  };
}

double? _price(PlaceKind kind, _Rng rng) => switch (kind) {
  .motorhomeArea => rng.next() < 0.4 ? 0 : (5 + rng.nextInt(11)).toDouble(),
  .campsite => (14 + rng.nextInt(22)).toDouble(),
  .parking || .nature || .restArea || .picnicArea || .offRoad => rng.next() < 0.7 ? 0 : null,
  .farm || .homestay => rng.next() < 0.6 ? 0 : (8 + rng.nextInt(8)).toDouble(),
  .serviceArea || .extraService => null,
};

String _prefix(PlaceKind kind) => switch (kind) {
  .motorhomeArea => 'Aire',
  .serviceArea => 'Borne',
  .campsite => 'Camping',
  .parking => 'Parking',
  .nature => 'Coin nature',
  .restArea => 'Aire de repos',
  .picnicArea => 'Pique-nique',
  .farm => 'Ferme',
  .homestay => 'Jardin',
  .offRoad => 'Piste',
  .extraService => 'Station',
};

typedef _Town = ({String name, String postcode, double lat, double lon});

const List<_Town> _towns = [
  (name: 'Lyon', postcode: '69001', lat: 45.7640, lon: 4.8357),
  (name: 'Annecy', postcode: '74000', lat: 45.8992, lon: 6.1294),
  (name: 'Bordeaux', postcode: '33000', lat: 44.8378, lon: -0.5792),
  (name: 'Nantes', postcode: '44000', lat: 47.2184, lon: -1.5536),
  (name: 'Brest', postcode: '29200', lat: 48.3904, lon: -4.4861),
  (name: 'Saint-Malo', postcode: '35400', lat: 48.6493, lon: -2.0257),
  (name: 'Rouen', postcode: '76000', lat: 49.4432, lon: 1.0999),
  (name: 'Lille', postcode: '59000', lat: 50.6292, lon: 3.0573),
  (name: 'Strasbourg', postcode: '67000', lat: 48.5734, lon: 7.7521),
  (name: 'Colmar', postcode: '68000', lat: 48.0794, lon: 7.3585),
  (name: 'Dijon', postcode: '21000', lat: 47.3220, lon: 5.0415),
  (name: 'Chamonix-Mont-Blanc', postcode: '74400', lat: 45.9237, lon: 6.8694),
  (name: 'Grenoble', postcode: '38000', lat: 45.1885, lon: 5.7245),
  (name: 'Briançon', postcode: '05100', lat: 44.8986, lon: 6.6430),
  (name: 'Nice', postcode: '06000', lat: 43.7102, lon: 7.2620),
  (name: 'Marseille', postcode: '13001', lat: 43.2965, lon: 5.3698),
  (name: 'Avignon', postcode: '84000', lat: 43.9493, lon: 4.8055),
  (name: 'Arles', postcode: '13200', lat: 43.6768, lon: 4.6303),
  (name: 'Montpellier', postcode: '34000', lat: 43.6108, lon: 3.8767),
  (name: 'Sète', postcode: '34200', lat: 43.4028, lon: 3.6928),
  (name: 'Perpignan', postcode: '66000', lat: 42.6887, lon: 2.8948),
  (name: 'Carcassonne', postcode: '11000', lat: 43.2130, lon: 2.3491),
  (name: 'Toulouse', postcode: '31000', lat: 43.6047, lon: 1.4442),
  (name: 'Albi', postcode: '81000', lat: 43.9289, lon: 2.1464),
  (name: 'Millau', postcode: '12100', lat: 44.0981, lon: 3.0777),
  (name: 'Clermont-Ferrand', postcode: '63000', lat: 45.7772, lon: 3.0870),
  (name: 'Le Puy-en-Velay', postcode: '43000', lat: 45.0434, lon: 3.8850),
  (name: 'Limoges', postcode: '87000', lat: 45.8336, lon: 1.2611),
  (name: 'Sarlat-la-Canéda', postcode: '24200', lat: 44.8890, lon: 1.2165),
  (name: 'Biarritz', postcode: '64200', lat: 43.4832, lon: -1.5586),
  (name: 'Pau', postcode: '64000', lat: 43.2951, lon: -0.3708),
  (name: 'La Rochelle', postcode: '17000', lat: 46.1603, lon: -1.1511),
  (name: 'Royan', postcode: '17200', lat: 45.6248, lon: -1.0291),
  (name: 'Tours', postcode: '37000', lat: 47.3941, lon: 0.6848),
  (name: 'Orléans', postcode: '45000', lat: 47.9030, lon: 1.9093),
  (name: 'Reims', postcode: '51100', lat: 49.2583, lon: 4.0317),
  (name: 'Metz', postcode: '57000', lat: 49.1193, lon: 6.1757),
  (name: 'Caen', postcode: '14000', lat: 49.1829, lon: -0.3707),
  (name: 'Bayeux', postcode: '14400', lat: 49.2764, lon: -0.7024),
  (name: 'Quimper', postcode: '29000', lat: 47.9960, lon: -4.1024),
  (name: 'Vannes', postcode: '56000', lat: 47.6582, lon: -2.7608),
  (name: 'Ajaccio', postcode: '20000', lat: 41.9192, lon: 8.7386),
  (name: 'Bastia', postcode: '20200', lat: 42.6977, lon: 9.4508),
  (name: 'Gap', postcode: '05000', lat: 44.5594, lon: 6.0786),
];

const _names = [
  'des Tilleuls',
  'du Lac Bleu',
  'des Trois Chênes',
  'de la Prairie',
  'du Vieux Moulin',
  'des Hirondelles',
  'de la Plage',
  'du Port',
  'des Vignes',
  'de la Source',
  'du Belvédère',
  'des Peupliers',
  'de la Forêt',
  'des Écluses',
  'du Château',
  'des Lavandes',
  'de la Rivière',
  'des Marais',
  'du Plateau',
  'des Cerisiers',
];

const _streets = [
  'rue des Exemples',
  'chemin du Lac',
  'avenue de la Gare',
  'route des Vignes',
  'impasse du Moulin',
  'quai du Port',
];

typedef _Text = ({String fr, String en, String de});

const List<_Text> _descriptions = [
  (
    fr: 'Lieu fictif généré pour la démonstration. Emplacements plats, calme la nuit, commerces à 5 minutes à pied.',
    en: 'Invented place for the demo. Level pitches, quiet at night, shops five minutes away on foot.',
    de: 'Erfundener Ort für die Demo. Ebene Stellplätze, nachts ruhig, Geschäfte fünf Minuten zu Fuß.',
  ),
  (
    fr: 'Lieu fictif. Grand parking goudronné en bord de rivière, ombragé l’été. Accès facile depuis la départementale.',
    en: 'Invented place. Large tarmac car park by the river, shaded in summer. Easy access from the main road.',
    de: 'Erfundener Ort. Großer asphaltierter Parkplatz am Fluss, im Sommer schattig. Leicht erreichbar.',
  ),
  (
    fr: 'Lieu fictif de démonstration : aire au pied du village, borne à jetons, vue dégagée sur la vallée.',
    en: 'Invented demo place: area below the village, token service point, open view over the valley.',
    de: 'Erfundener Demo-Ort: Platz unterhalb des Dorfes, Ver- und Entsorgung mit Jetons, freier Blick ins Tal.',
  ),
  (
    fr: 'Lieu fictif. Terrain herbeux, quelques places en dévers, prévoir des cales. Très calme.',
    en: 'Invented place. Grassy ground, a few sloping pitches, bring levelling blocks. Very quiet.',
    de: 'Erfundener Ort. Wiese, einige schräge Plätze, Auffahrkeile mitbringen. Sehr ruhig.',
  ),
  (
    fr: 'Lieu fictif de démonstration, proche du centre historique. Stationnement limité à 48 h.',
    en: 'Invented demo place near the old town. Parking limited to 48 hours.',
    de: 'Erfundener Demo-Ort nahe der Altstadt. Parken auf 48 Stunden begrenzt.',
  ),
];

/// Photos and reviews of a demo place, the way the server would answer: a
/// few synthetic photos at the image proxy's URLs under [apiBase] (the demo
/// server draws them), and invented reviews.
({List<Photo> photos, List<Review> reviews}) demoExtras(Place place, {required Uri apiBase}) {
  final seed = place.id.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7FFFFFFF);
  final index = int.parse(place.id.substring(place.id.lastIndexOf('-') + 1));
  final rng = _Rng(seed);
  final rating = place.ratings.where((r) => r.sourceId == demoCommunitySource.id).firstOrNull;
  final photoCount = rating == null ? 0 : 1 + rng.nextInt(5);
  final photos = [
    for (var i = 0; i < photoCount; i++)
      () {
        final n = 1 + (seed + i) % 6;
        return Photo(
          id: _demoId(1, index * 100 + i),
          sourceId: demoCommunitySource.id,
          thumbUrl: '$apiBase/media/demo-$n/thumb',
          largeUrl: '$apiBase/media/demo-$n/large',
        );
      }(),
  ];
  final count = rating?.count ?? 0;
  final reviews = [
    for (var i = 0; i < count && i < 60; i++)
      Review(
        id: _demoId(2, index * 100 + i),
        sourceId: demoCommunitySource.id,
        rating: 2 + rng.nextInt(4),
        text: _reviews[rng.nextInt(_reviews.length)],
        lang: 'fr',
        authorName: 'Voyageur démo ${1 + rng.nextInt(400)}',
        authorVehicle: ReviewVehicle.values[rng.nextInt(ReviewVehicle.values.length)],
        visitedAt: DateTime(2026, 9, 2).subtract(Duration(days: i * 9 + rng.nextInt(9))),
        createdAt: DateTime.utc(2026, 9, 3).subtract(Duration(days: i * 9 + rng.nextInt(9))),
      ),
  ];
  return (photos: photos, reviews: reviews);
}

const _reviews = [
  'Avis inventé pour la démo. Nuit calme, accueil sympathique, on reviendra.',
  'Avis de démonstration : un peu de bruit le matin avec les livraisons, sinon parfait.',
  'Avis fictif. Borne en panne lors de notre passage, mais l’eau était disponible au village.',
  'Avis inventé. Très belle vue au coucher du soleil, places un peu étroites pour un 7 m.',
  'Avis de démonstration : propre, gratuit, idéal pour une étape.',
];

/// A UUID-shaped id, as the API gives: [kind] tells places, photos and
/// reviews apart, [n] numbers them, and the last group stays a plain number.
String _demoId(int kind, int n) =>
    '00000000-${kind.toString().padLeft(4, '0')}-4000-8000-${n.toString().padLeft(12, '0')}';

/// Opening hours of the demo, as the OSM text and the weekly spans (minutes
/// after local midnight, per ISO weekday) it means: the demo builds the
/// intervals the server would send without parsing the text.
typedef _Hours = ({String raw, Map<int, List<(int, int)>> week});

const _everyDay = [1, 2, 3, 4, 5, 6, 7];

final List<_Hours> _hours = [
  (
    raw: '24/7',
    week: {
      for (final d in _everyDay) d: const [(0, 1440)],
    },
  ),
  (
    raw: 'Mo-Su 08:00-20:00',
    week: {
      for (final d in _everyDay) d: const [(480, 1200)],
    },
  ),
  (
    raw: 'Mo-Fr 08:00-18:00; Sa 09:00-12:00',
    week: {
      for (final d in [1, 2, 3, 4, 5]) d: const [(480, 1080)],
      6: const [(540, 720)],
    },
  ),
  (
    raw: 'Mo-Su 07:00-22:00',
    week: {
      for (final d in _everyDay) d: const [(420, 1320)],
    },
  ),
  (
    raw: 'Fr-Su 18:00-02:00',
    week: {
      for (final d in [5, 6, 7]) d: const [(1080, 1560)],
    },
  ),
  (
    raw: 'Tu-Su 09:00-12:00,14:00-19:00',
    week: {
      for (final d in [2, 3, 4, 5, 6, 7]) d: const [(540, 720), (840, 1140)],
    },
  ),
];

/// The demo towns are French: their hours are read on the clock of France,
/// as the server reads them in each place's zone, never on the clock of the
/// machine running the demo or the tests.
const PlaceZone _zone = PlaceZone.central;

/// The UTC intervals of [hours] from the day before [now] over the window.
List<OpeningInterval> _intervals(_Hours hours, DateTime now) {
  final wall = _zone.wallClock(now);
  final first = DateTime.utc(wall.year, wall.month, wall.day - 1);
  final out = <OpeningInterval>[];
  for (var d = 0; d <= openingWindow.inDays + 1; d++) {
    final day = DateTime.utc(first.year, first.month, first.day + d);
    for (final (start, end) in hours.week[day.weekday] ?? const <(int, int)>[]) {
      out.add(
        OpeningInterval(
          _zone.instantOf(DateTime.utc(day.year, day.month, day.day, 0, start)),
          _zone.instantOf(DateTime.utc(day.year, day.month, day.day, 0, end)),
        ),
      );
    }
  }
  return out;
}

/// Where the server's window ends: 14 days from midnight, in the place's
/// zone, of the day it computed the intervals.
DateTime _windowEnd(DateTime now) {
  final wall = _zone.wallClock(now);
  return _zone.instantOf(DateTime.utc(wall.year, wall.month, wall.day + openingWindow.inDays));
}

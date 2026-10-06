import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// The moment every widget test lives at: Tuesday 6 October 2026, 10:30,
/// local time.
final testNow = DateTime(2026, 10, 6, 10, 30);

const osm = Source(
  id: 'osm',
  name: 'OpenStreetMap',
  licence: 'ODbL-1.0',
  attribution: '© OpenStreetMap contributors',
  url: 'https://www.openstreetmap.org',
);

const atoutFrance = Source(
  id: 'atout-france',
  name: 'Atout France',
  licence: 'Licence Ouverte 2.0',
  attribution: 'Classement des campings, Licence Ouverte 2.0.',
  url: 'https://lunaway.net',
);

/// Every day 08:00 to 20:00 local, over the window that starts the day
/// before [testNow].
List<OpeningInterval> dailyEightToEight() => [
  for (var d = -1; d < 15; d++)
    OpeningInterval(DateTime(2026, 10, 6 + d, 8).toUtc(), DateTime(2026, 10, 6 + d, 20).toUtc()),
];

final lakeArea = Place(
  id: 'test-lake',
  name: 'Aire du Lac Bleu (démo)',
  kind: PlaceKind.motorhomeArea,
  lat: 45.8992,
  lon: 6.1294,
  overnight: OvernightStatus.allowed,
  services: const {
    Service.drinkingWater,
    Service.greyWater,
    Service.blackWater,
    Service.electricity,
  },
  activities: const {Activity.hiking, Activity.swimming},
  description: 'Aire fictive au bord du lac.',
  address: const Address(
    street: '12 chemin du Lac',
    postcode: '74000',
    city: 'Annecy',
    countryCode: 'FR',
  ),
  priceParkingEur: 12,
  priceServicesEur: 3,
  capacity: 25,
  openingHours: 'Mo-Su 08:00-20:00',
  openingHoursParsed: true,
  openingIntervals: dailyEightToEight(),
  openingValidUntil: DateTime(2026, 10, 19).toUtc(),
  website: 'https://lunaway.net/demo',
  phone: '+33 4 00 00 00 00',
  lastConfirmedAt: DateTime.utc(2026, 7),
  updatedAt: DateTime.utc(2026, 9, 28),
  sources: [
    PlaceSource(
      source: osm,
      externalId: 'node/1',
      externalUrl: 'https://www.openstreetmap.org/node/1',
      fetchedAt: DateTime.utc(2026, 10, 3),
    ),
    PlaceSource(
      source: atoutFrance,
      externalId: 'atout/1',
      fetchedAt: DateTime.utc(2026, 10, 6),
      matchScore: 0.93,
    ),
  ],
  descriptions: const [
    LocalizedText(lang: 'de', text: 'Erfundener Platz am See.', sourceId: 'community'),
    LocalizedText(lang: 'en', text: 'Invented area by the lake.', sourceId: 'community'),
  ],
  ratings: const [
    SourceRating(sourceId: 'community', average: 4.3, count: 128),
    SourceRating(sourceId: 'atout-france', average: 4, count: 2),
  ],
);

/// At the coordinates the brief quotes, so the copy format is checked on
/// a known value.
final dayParking = Place(
  id: 'test-day',
  name: 'Parking des Tilleuls (démo)',
  kind: PlaceKind.parking,
  lat: 45.7629,
  lon: 4.831697,
  overnight: OvernightStatus.dayOnly,
  services: const {Service.wasteBin},
  address: const Address(city: 'Lyon', postcode: '69001'),
  priceParkingEur: 0,
  maxHeightM: 2.1,
  updatedAt: DateTime.utc(2026, 9),
  sources: [PlaceSource(source: osm, externalId: 'way/2', fetchedAt: DateTime.utc(2026, 10, 3))],
);

final campsite = Place(
  id: 'test-camp',
  name: 'Camping des Peupliers (démo)',
  kind: PlaceKind.campsite,
  lat: 47.2184,
  lon: -1.5536,
  overnight: OvernightStatus.allowed,
  services: const {
    Service.drinkingWater,
    Service.toilets,
    Service.showers,
    Service.electricity,
    Service.wifi,
  },
  address: const Address(city: 'Nantes', postcode: '44000'),
  priceParkingEur: 22.5,
  stars: 3,
  updatedAt: DateTime.utc(2026, 9, 20),
  lastConfirmedAt: DateTime.utc(2024, 3),
  sources: [
    PlaceSource(source: osm, externalId: 'node/3', fetchedAt: DateTime.utc(2026, 10, 3)),
    PlaceSource(
      source: atoutFrance,
      externalId: 'af-44-0003',
      fetchedAt: DateTime.utc(2026, 10, 2),
      matchScore: 0.93,
    ),
  ],
);

final unnamedParking = Place(
  id: 'test-unnamed',
  kind: PlaceKind.parking,
  lat: 48.6493,
  lon: -2.0257,
  overnight: OvernightStatus.tolerated,
  address: const Address(city: 'Saint-Malo'),
  updatedAt: DateTime.utc(2026, 9, 20),
  sources: [PlaceSource(source: osm, externalId: 'way/4', fetchedAt: DateTime.utc(2026, 10, 3))],
);

final serviceArea = Place(
  id: 'test-service',
  name: 'Borne du Port (démo)',
  kind: PlaceKind.serviceArea,
  lat: 43.4028,
  lon: 3.6928,
  overnight: OvernightStatus.dayOnly,
  services: const {Service.drinkingWater, Service.greyWater},
  address: const Address(city: 'Sète'),
  updatedAt: DateTime.utc(2026, 9, 20),
  sources: [PlaceSource(source: osm, externalId: 'node/5', fetchedAt: DateTime.utc(2026, 10, 3))],
);

final List<Place> samplePlaces = [lakeArea, dayParking, campsite, unnamedParking, serviceArea];

/// The API the tests' configuration points at (the public one): photos
/// are served at its image proxy's paths, by the demo server in tests.
const testApiBase = 'https://api.lunaway.net';

final List<Photo> samplePhotos = [
  for (var i = 1; i <= 3; i++)
    Photo(
      id: 'photo-$i',
      sourceId: 'community',
      thumbUrl: '$testApiBase/media/demo-$i/thumb',
      largeUrl: '$testApiBase/media/demo-$i/large',
    ),
];

final List<Review> sampleReviews = [
  for (var i = 1; i <= 5; i++)
    Review(
      id: 'review-$i',
      sourceId: 'community',
      rating: 6 - (i % 5 + 1),
      text: 'Avis inventé numéro $i.',
      lang: 'fr',
      authorName: 'Voyageur démo $i',
      authorVehicle: ReviewVehicle.campervan,
      createdAt: DateTime.utc(2026, 9, 10 - i),
    ),
];

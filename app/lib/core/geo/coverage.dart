import 'package:lunaway/core/geo/geo.dart';

/// The area the places cover: the box of each country the backend imports,
/// as the Europe routing graph cuts it
/// (`backend/crates/lunaway-domain/data/routing-coverage.poly`, which also
/// holds Morocco, reached by the ferries from Spain), widened to the tenth
/// of a degree. The sea around the boxes holds no place: a view kept with
/// its centre out there is not opened again. test/unit/coverage_test.dart
/// keeps these equal to that file.
const placeCoverage = <GeoBounds>[
  // europe/france
  GeoBounds(south: 41.2, west: -7, north: 51.5, east: 9.9),
  // europe/spain
  GeoBounds(south: 35.2, west: -9.8, north: 44.2, east: 5.1),
  // africa/canary-islands
  GeoBounds(south: 26.3, west: -19, north: 30.3, east: -12.4),
  // europe/portugal
  GeoBounds(south: 29.7, west: -31.6, north: 42.2, east: -6.1),
  // europe/italy
  GeoBounds(south: 35, west: 6.6, north: 47.2, east: 19.2),
  // europe/germany
  GeoBounds(south: 47.2, west: 5.8, north: 55.2, east: 15.1),
  // europe/austria
  GeoBounds(south: 46.3, west: 9.5, north: 49.1, east: 17.2),
  // europe/switzerland
  GeoBounds(south: 45.8, west: 5.9, north: 47.9, east: 10.5),
  // europe/liechtenstein
  GeoBounds(south: 47, west: 9.4, north: 47.3, east: 9.7),
  // europe/belgium
  GeoBounds(south: 49.4, west: 2.3, north: 51.6, east: 6.5),
  // europe/netherlands
  GeoBounds(south: 50.7, west: 2.9, north: 54.1, east: 7.3),
  // europe/luxembourg
  GeoBounds(south: 49.4, west: 5.7, north: 50.2, east: 6.6),
  // europe/united-kingdom
  GeoBounds(south: 49.4, west: -14.9, north: 61.2, east: 2.7),
  // europe/ireland-and-northern-ireland
  GeoBounds(south: 49.6, west: -14.5, north: 56.9, east: -5),
  // europe/denmark
  GeoBounds(south: 54.4, west: 7.7, north: 58.1, east: 15.7),
  // europe/norway
  GeoBounds(south: 57.5, west: -11.4, north: 81.1, east: 35.6),
  // europe/sweden
  GeoBounds(south: 55, west: 10.5, north: 69.1, east: 24.3),
  // europe/finland
  GeoBounds(south: 59.2, west: 19, north: 70.1, east: 31.7),
  // europe/croatia
  GeoBounds(south: 42.1, west: 13, north: 46.6, east: 19.5),
  // europe/slovenia
  GeoBounds(south: 45.4, west: 13.3, north: 46.9, east: 16.7),
  // europe/greece
  GeoBounds(south: 34.5, west: 18.9, north: 41.8, east: 29.7),
  // europe/poland
  GeoBounds(south: 48.9, west: 13.9, north: 55.3, east: 24.2),
  // europe/czech-republic
  GeoBounds(south: 48.5, west: 12, north: 51.1, east: 18.9),
  // europe/andorra
  GeoBounds(south: 42.4, west: 1.4, north: 42.7, east: 1.8),
  // africa/morocco
  GeoBounds(south: 20.4, west: -18.2, north: 36.1, east: -0.9),
];

/// Whether [p] lies in the area the places cover ([placeCoverage]).
bool inPlaceCoverage(LatLng p) => placeCoverage.any((b) => b.contains(p));

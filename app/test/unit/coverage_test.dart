import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/coverage.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/data/last_view.dart';

import '../helpers/pump.dart' show memoryDatabase;

/// The box of each ring of the routing graph's cut, widened to the tenth
/// of a degree, in the order of the file.
List<GeoBounds> _boxesOfPoly(String text) {
  final boxes = <GeoBounds>[];
  List<LatLng>? ring;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('extract ')) continue;
    final parts = line.split(RegExp(r'\s+'));
    final lon = parts.length == 2 ? double.tryParse(parts[0]) : null;
    final lat = parts.length == 2 ? double.tryParse(parts[1]) : null;
    if (ring != null && lon != null && lat != null) {
      ring.add(LatLng(lat, lon));
    } else if (line == 'END') {
      if (ring != null) {
        final box = GeoBounds.around(ring)!;
        double down(double v) => (v * 10 + 1e-9).floorToDouble() / 10;
        double up(double v) => (v * 10 - 1e-9).ceilToDouble() / 10;
        boxes.add(
          GeoBounds(
            south: down(box.south),
            west: down(box.west),
            north: up(box.north),
            east: up(box.east),
          ),
        );
      }
      ring = null;
    } else {
      // The polygon's name, then a ring's: the points follow.
      ring = [];
    }
  }
  return boxes;
}

void main() {
  test('the area the places cover is the box of each country the routing graph cuts', () {
    final poly = File('../backend/crates/lunaway-domain/data/routing-coverage.poly')
        .readAsStringSync();
    final boxes = _boxesOfPoly(poly);
    expect(boxes, hasLength(placeCoverage.length), reason: "one box per country's cut");
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      final c = placeCoverage[i];
      for (final (name, kept, cut) in [
        ('south', c.south, b.south),
        ('west', c.west, b.west),
        ('north', c.north, b.north),
        ('east', c.east, b.east),
      ]) {
        expect(kept, closeTo(cut, 1e-9), reason: 'box $i, $name: copy it from the .poly file');
      }
    }
  });

  test('the views a phone page once kept out at sea are not covered, the countries are', () {
    for (final sea in const [LatLng(46.5, -9.9), LatLng(46.5, -11.8), LatLng(46.5, -25.8)]) {
      expect(inPlaceCoverage(sea), isFalse, reason: '$sea');
    }
    for (final land in const [
      LatLng(46.6, 2.5), // France
      LatLng(45.9, 6.1), // Annecy
      LatLng(40.4, -3.7), // Madrid
      LatLng(28.1, -15.4), // Las Palmas
      LatLng(59.9, 10.7), // Oslo
    ]) {
      expect(inPlaceCoverage(land), isTrue, reason: '$land');
    }
  });

  test('a view kept out at sea opens on the first view instead', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final store = DriftLastViewStore(CacheDatabase(memoryDatabase()));
    await store.save(const LatLng(46.5, -11.8), 3.9);
    expect(await store.load(), isNull);
    await store.save(const LatLng(45.9, 6.1), 9);
    expect((await store.load())?.center, const LatLng(45.9, 6.1));
  });
}

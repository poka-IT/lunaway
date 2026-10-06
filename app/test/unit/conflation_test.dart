import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

import '../support/conflation.dart';

/// The vectors the Rust scorer runs too: both implementations must give the
/// same normalisations, scores and decisions.
final _vectors = File('../schema/conflation-vectors.json');

PlaceKind _kind(String code) => PlaceKind.fromWire(code.toUpperCase());

MatchCandidate _record(Map<String, dynamic> r) => MatchCandidate.prepare(
  source: r['source'] as String,
  kind: _kind(r['kind'] as String),
  position: LatLng((r['lat'] as num).toDouble(), (r['lon'] as num).toDouble()),
  accuracyM: (r['accuracyM'] as num?)?.toDouble() ?? 0,
  name: r['name'] as String?,
  osm: r['osm'] as String?,
  wikidata: r['wikidata'] as String?,
  phone: r['phone'] as String?,
  website: r['website'] as String?,
  postcode: r['postcode'] as String?,
  cityCode: r['cityCode'] as String?,
);

void main() {
  test('the shared vectors file is present', () {
    expect(
      _vectors.existsSync(),
      isTrue,
      reason: 'schema/conflation-vectors.json is written by the backend',
    );
  });

  if (!_vectors.existsSync()) return;
  final vectors = jsonDecode(_vectors.readAsStringSync()) as Map<String, dynamic>;
  final parameters = vectors['parameters'] as Map<String, dynamic>;

  test('the Dart constants are the shared parameters', () {
    expect(Conflation.mergeThreshold, parameters['mergeThreshold']);
    expect(Conflation.reviewThreshold, parameters['reviewThreshold']);
    final weights = parameters['weights'] as Map<String, dynamic>;
    expect(Conflation.weightDistance, weights['distance']);
    expect(Conflation.weightName, weights['name']);
    expect(Conflation.weightMunicipality, weights['municipality']);
    expect(Conflation.nameUnknown, parameters['nameUnknown']);
    expect(Conflation.accuracyCapM, parameters['accuracyCapM']);
    expect(Conflation.globalIdFloor, parameters['globalIdFloor']);
    expect(Conflation.globalIdReachM, parameters['globalIdReachM']);
    expect(Conflation.localIdFloor, parameters['localIdFloor']);
    (parameters['kindRadiusM'] as Map<String, dynamic>).forEach((code, radius) {
      expect(Conflation.kindRadiusM(_kind(code)), radius, reason: code);
    });
    for (final pair in parameters['kindCompatibility'] as List<dynamic>) {
      final p = pair as List<dynamic>;
      expect(
        Conflation.kindCompatibility(_kind(p[0] as String), _kind(p[1] as String)),
        p[2],
        reason: '$p',
      );
    }
    expect(Conflation.genericWords, (parameters['genericWords'] as List<dynamic>).toSet());
    expect(Conflation.abbreviations, parameters['abbreviations']);
    expect(Conflation.ligatures, parameters['ligatures']);
    expect(Conflation.platformHosts, (parameters['platformHosts'] as List<dynamic>).toSet());
    expect(LatLng.earthRadiusM, parameters['earthRadiusM']);
  });

  test('kind compatibility reads the same both ways, and a kind fully matches itself', () {
    for (final a in PlaceKind.values) {
      expect(Conflation.kindCompatibility(a, a), 1, reason: '$a');
      for (final b in PlaceKind.values) {
        expect(
          Conflation.kindCompatibility(a, b),
          Conflation.kindCompatibility(b, a),
          reason: '$a, $b',
        );
      }
    }
    expect(Conflation.kindCompatibility(PlaceKind.farm, PlaceKind.homestay), 0.8);
    expect(Conflation.kindCompatibility(PlaceKind.offRoad, PlaceKind.campsite), 0);
  });

  test('ligatures expand when names fold', () {
    expect(Conflation.fold('Œuilly-Ærøskøbing Straße Łódź'), 'oeuilly aeroskobing strasse lodz');
  });

  group('normalisation', () {
    for (final v in vectors['names'] as List<dynamic>) {
      final m = v as Map<String, dynamic>;
      test(
        'name "${m['input']}"',
        () => expect(Conflation.normalizeName(m['input'] as String), m['normalized']),
      );
    }
    for (final v in vectors['phones'] as List<dynamic>) {
      final m = v as Map<String, dynamic>;
      test(
        'phone "${m['input']}"',
        () => expect(Conflation.normalizePhone(m['input'] as String), m['normalized']),
      );
    }
    for (final v in vectors['websites'] as List<dynamic>) {
      final m = v as Map<String, dynamic>;
      test(
        'website "${m['input']}"',
        () => expect(Conflation.normalizeWebsite(m['input'] as String), m['normalized']),
      );
    }
  });

  group('cases', () {
    for (final c in vectors['cases'] as List<dynamic>) {
      final m = c as Map<String, dynamic>;
      test('${m['id']}: ${m['why']}', () {
        final a = _record(m['a'] as Map<String, dynamic>);
        final b = _record(m['b'] as Map<String, dynamic>);
        final ab = Conflation.score(a, b);
        final ba = Conflation.score(b, a);
        expect(ab.decision.name, m['expected']);
        expect(ab.score, closeTo((m['score'] as num).toDouble(), 0.001));
        expect(ba.score, closeTo(ab.score, 1e-12), reason: 'scoring is symmetric');
        expect(ba.decision, ab.decision);
      });
    }
  });
}

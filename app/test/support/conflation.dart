// A Dart port of the backend's place matching (crates/lunaway-domain),
// kept with the tests: the app no longer conflates on the device (the
// server ingests every source), but the port still checks, against the
// shared vectors (schema/conflation-vectors.json), that the parameters and
// normalisations the backend publishes are self-consistent from a second
// implementation.
import 'dart:math' as math;

import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// The match score of two records, ported from the Rust domain crate
/// (`backend/crates/lunaway-domain/src/conflation/`), so the device can tell
/// whether two records are one spot the way the server does (a place the
/// user is about to add that already exists, for instance).
/// `schema/conflation-vectors.json` holds shared cases both implementations
/// must pass, so the parameters below change only together with the Rust
/// ones.
abstract final class Conflation {
  static const mergeThreshold = 0.85;
  static const reviewThreshold = 0.6;
  static const weightDistance = 0.45;
  static const weightName = 0.4;
  static const weightMunicipality = 0.1;
  static const nameUnknown = 0.5;
  static const accuracyCapM = 500.0;
  static const globalIdFloor = 0.95;
  static const localIdFloor = 0.9;
  static const maxKindRadiusM = 300.0;
  static const double globalIdReachM = maxKindRadiusM;

  static double kindRadiusM(PlaceKind kind) => switch (kind) {
    .parking || .serviceArea || .extraService => 60,
    .picnicArea || .nature => 100,
    .motorhomeArea || .restArea || .offRoad => 150,
    .homestay => 200,
    .campsite || .farm => 300,
  };

  static const List<(PlaceKind, PlaceKind, double)> kindPairs = [
    (.motorhomeArea, .parking, 0.9),
    (.motorhomeArea, .serviceArea, 0.9),
    (.motorhomeArea, .campsite, 0.8),
    (.motorhomeArea, .restArea, 0.6),
    (.motorhomeArea, .farm, 0.6),
    (.serviceArea, .parking, 0.7),
    (.serviceArea, .extraService, 0.7),
    (.serviceArea, .restArea, 0.6),
    (.serviceArea, .campsite, 0.5),
    (.parking, .restArea, 0.8),
    (.parking, .nature, 0.6),
    (.parking, .picnicArea, 0.6),
    (.restArea, .picnicArea, 0.8),
    (.nature, .picnicArea, 0.6),
    (.nature, .offRoad, 0.8),
    (.farm, .homestay, 0.8),
    (.farm, .campsite, 0.6),
    (.homestay, .campsite, 0.4),
  ];

  static double kindCompatibility(PlaceKind a, PlaceKind b) {
    if (a == b) return 1;
    for (final (x, y, v) in kindPairs) {
      if ((x == a && y == b) || (x == b && y == a)) return v;
    }
    return 0;
  }

  /// Words that say what kind of spot a place is rather than which one.
  static const genericWords = {
    'a', 'au', 'aux', 'd', 'de', 'des', 'du', 'en', 'et', 'l', 'la', 'le', 'les', 'sur', 'sous', //
    'and', 'of', 'the', //
    'am', 'an', 'auf', 'bei', 'beim', 'das', 'dem', 'den', 'der', 'die', 'im', 'in', 'und', //
    'zum', 'zur', 'al', 'del', 'el', 'las', 'los', 'y', 'da', 'dei', 'della', 'delle', 'dello', //
    'di', 'il', //
    'aire', 'aires', 'area', 'camp', 'camper', 'campers', 'camperplaats', 'camping', 'campings', //
    'campingcar', 'campingcars', 'car', 'cars', 'caravan', 'caravane', 'caravanes', 'caravaning', //
    'cc', 'motorhome', 'motorhomes', 'parking', 'parkings', 'site', 'sosta', 'stationnement', //
    'stellplatz', 'aparcamiento', 'autocaravana', 'autocaravanas', 'campeggio', 'campingplatz', //
    'parcheggio', 'parkplatz', 'wohnmobil', 'wohnmobile', 'wohnmobilstellplatz', //
    'accueil', 'communal', 'communale', 'municipal', 'municipale', 'municipaux', 'naturel', //
    'naturelle', 'service', 'services',
  };

  static const abbreviations = {'st': 'saint', 'ste': 'sainte'};

  static const ligatures = {
    'æ': 'ae',
    'Æ': 'ae',
    'œ': 'oe',
    'Œ': 'oe',
    'ß': 'ss',
    'ẞ': 'ss',
    'ø': 'o',
    'Ø': 'o',
    'đ': 'd',
    'Đ': 'd',
    'ł': 'l',
    'Ł': 'l',
    'ı': 'i',
  };

  static final _alphanumeric = RegExp(r'^[\p{L}\p{N}]$', unicode: true);

  /// Compatibility decomposition, accents dropped, ligatures expanded, lower
  /// case, anything but letters and digits turned into one space.
  static String fold(String s) {
    final out = StringBuffer();
    var pendingSpace = false;
    void push(String c) {
      if (_alphanumeric.hasMatch(c)) {
        if (pendingSpace && out.isNotEmpty) out.write(' ');
        pendingSpace = false;
        out.write(c.toLowerCase());
      } else {
        pendingSpace = true;
      }
    }

    for (final rune in unorm.nfkd(s).runes) {
      if (_isCombiningMark(rune)) continue;
      final c = String.fromCharCode(rune);
      final expanded = ligatures[c];
      if (expanded != null) {
        expanded.split('').forEach(push);
      } else {
        push(c);
      }
    }
    return out.toString();
  }

  static bool _isCombiningMark(int r) =>
      (r >= 0x0300 && r <= 0x036F) ||
      (r >= 0x1AB0 && r <= 0x1AFF) ||
      (r >= 0x1DC0 && r <= 0x1DFF) ||
      (r >= 0x20D0 && r <= 0x20FF) ||
      (r >= 0xFE20 && r <= 0xFE2F);

  /// The identifying words of a folded name, in order.
  static List<String> coreTokens(String folded) => [
    for (final t in folded.split(' '))
      if (t.isNotEmpty && !genericWords.contains(abbreviations[t] ?? t)) abbreviations[t] ?? t,
  ];

  static String normalizeName(String raw) => coreTokens(fold(raw)).join(' ');

  /// `+<country><number>`, or null under eight digits; a ten-digit number
  /// starting with 0 is read as French.
  static String? normalizePhone(String raw) {
    final first = raw.split(RegExp('[;,/]')).first.trim();
    final plus = first.startsWith('+');
    var digits = first.replaceAll(RegExp('[^0-9]'), '');
    var international = plus;
    if (!plus && digits.startsWith('00')) {
      digits = digits.substring(2);
      international = true;
    }
    final String normalised;
    if (international) {
      normalised = digits.startsWith('330') ? '+33${digits.substring(3)}' : '+$digits';
    } else if (digits.length == 10 && digits.startsWith('0')) {
      normalised = '+33${digits.substring(1)}';
    } else {
      return null;
    }
    return normalised.length > 8 ? normalised : null;
  }

  static const platformHosts = {
    'facebook.com',
    'fb.com',
    'instagram.com',
    'google.com',
    'sites.google.com',
    'booking.com',
    'airbnb.fr',
    'airbnb.com',
    'tripadvisor.fr',
    'tripadvisor.com',
  };

  /// `host/path`, lower case, without scheme, `www.`, query, fragment or
  /// trailing slash; null for a bare platform address.
  static String? normalizeWebsite(String raw) {
    final first = raw.split(RegExp('[; ]')).where((s) => s.isNotEmpty).firstOrNull?.trim();
    if (first == null) return null;
    final lower = first.toLowerCase();
    var rest = lower.startsWith('https://')
        ? lower.substring(8)
        : lower.startsWith('http://')
        ? lower.substring(7)
        : lower;
    if (rest.startsWith('www.')) rest = rest.substring(4);
    final cut = rest.indexOf(RegExp('[?#]'));
    var trimmed = cut < 0 ? rest : rest.substring(0, cut);
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final slash = trimmed.indexOf('/');
    final host = slash < 0 ? trimmed : trimmed.substring(0, slash);
    final path = slash < 0 ? '' : trimmed.substring(slash + 1);
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) return null;
    if (path.isEmpty && platformHosts.contains(host)) return null;
    return trimmed;
  }

  static String? normalizeWikidata(String raw) {
    final t = raw.trim();
    if (!t.startsWith('Q') && !t.startsWith('q')) return null;
    final digits = t.substring(1);
    if (digits.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
    return 'Q$digits';
  }

  /// Trigrams the way PostgreSQL's pg_trgm builds them: each word padded with
  /// two spaces in front and one behind. Sorted and deduplicated.
  static List<String> trigrams(String folded) {
    final out = <String>{};
    for (final word in folded.split(' ')) {
      if (word.isEmpty) continue;
      final padded = '  $word '.runes.toList();
      for (var i = 0; i + 3 <= padded.length; i++) {
        out.add(String.fromCharCodes(padded.sublist(i, i + 3)));
      }
    }
    return out.toList()..sort(_compareCodePoints);
  }

  static int _compareCodePoints(String a, String b) {
    final ra = a.runes.toList();
    final rb = b.runes.toList();
    for (var i = 0; i < math.min(ra.length, rb.length); i++) {
      if (ra[i] != rb[i]) return ra[i] - rb[i];
    }
    return ra.length - rb.length;
  }

  static double trigramSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shared = a.toSet().intersection(b.toSet()).length;
    return shared / (a.length + b.length - shared);
  }

  static double tokenContainment(List<String> a, List<String> b) {
    final smaller = math.min(a.length, b.length);
    if (smaller == 0) return 0;
    return a.toSet().intersection(b.toSet()).length / smaller;
  }

  static MatchScore score(MatchCandidate a, MatchCandidate b) {
    final distanceM = a.position.distanceTo(b.position);
    final effective = math.max(0, distanceM - (a.accuracyM + b.accuracyM)).toDouble();
    final radius = math.max(kindRadiusM(a.kind), kindRadiusM(b.kind));
    // Quadratic decay: flat near the spot, steep towards the radius.
    final distance = math.max(0, 1 - math.pow(effective / radius, 2)).toDouble();
    final name = _nameComponent(a, b);
    final kind = kindCompatibility(a.kind, b.kind);
    final municipality = _same(a.cityCode, b.cityCode) ?? _same(a.postcode, b.postcode);

    // A missing name is neutral: it leaves the mean, as an unknown
    // municipality does.
    final named = a.folded != null && b.folded != null;
    var weighted = weightDistance * distance + (named ? weightName * name : 0);
    var weights = weightDistance + (named ? weightName : 0);
    if (municipality != null) {
      weighted += weightMunicipality * (municipality ? 1 : 0);
      weights += weightMunicipality;
    }
    final base = weighted / weights;
    var score = base * kind;
    var reason = MatchReason.score;

    final sameOsm = _same(a.osm, b.osm);
    final sameWikidata = _same(a.wikidata, b.wikidata);
    // A Wikidata item for a lake or a town is shared by spots far apart: a
    // shared identifier counts only within the reach the server compares.
    final sharedGlobal = effective > globalIdReachM
        ? null
        : sameOsm == true
        ? IdentifierKind.osm
        : sameWikidata == true
        ? IdentifierKind.wikidata
        : null;
    // Every OSM record names its own element, so a node and a way of one
    // campsite always differ there: the OSM element separates records only
    // when another source cites one.
    final conflicting = a.source != b.source && sameOsm == false
        ? IdentifierKind.osm
        : sameWikidata == false
        ? IdentifierKind.wikidata
        : null;
    final sharedLocal = distance > 0
        ? (_same(a.phone, b.phone) == true
              ? IdentifierKind.phone
              : _same(a.website, b.website) == true
              ? IdentifierKind.website
              : null)
        : null;
    IdentifierKind? sharedIdentifier;

    if (kind == 0) {
      reason = MatchReason.incompatibleKinds;
    } else if (conflicting != null && sharedGlobal == null) {
      score = 0;
      reason = MatchReason.conflictingIdentifier;
    } else if (sharedGlobal != null) {
      sharedIdentifier = sharedGlobal;
      if (globalIdFloor * kind > score) {
        score = globalIdFloor * kind;
        reason = MatchReason.sharedIdentifier;
      }
    } else if (sharedLocal != null) {
      sharedIdentifier = sharedLocal;
      if (localIdFloor * kind > score) {
        score = localIdFloor * kind;
        reason = MatchReason.sharedIdentifier;
      }
    }

    var decision = score >= mergeThreshold
        ? MatchDecision.merge
        : score >= reviewThreshold
        ? MatchDecision.review
        : MatchDecision.distinct;
    if (a.source == b.source && decision == MatchDecision.merge) {
      decision = MatchDecision.review;
      reason = MatchReason.sameSource;
    }
    return MatchScore(
      score: score,
      decision: decision,
      reason: reason,
      distanceM: distanceM,
      distance: distance,
      name: name,
      kind: kind,
      municipality: municipality == null ? null : (municipality ? 1 : 0),
      base: base,
      sharedIdentifier: sharedIdentifier,
      conflictingIdentifier: sharedGlobal == null ? conflicting : null,
    );
  }

  static double _nameComponent(MatchCandidate a, MatchCandidate b) {
    if (a.folded == null || b.folded == null) return nameUnknown;
    final useCore = a.coreTokens.isNotEmpty && b.coreTokens.isNotEmpty;
    final ta = useCore ? a.coreTokens : a.foldedTokens;
    final tb = useCore ? b.coreTokens : b.foldedTokens;
    final ga = useCore ? a.coreTrigrams : a.foldedTrigrams;
    final gb = useCore ? b.coreTrigrams : b.foldedTrigrams;
    return math.max(trigramSimilarity(ga, gb), tokenContainment(ta, tb));
  }

  static bool? _same(String? a, String? b) => a == null || b == null ? null : a == b;
}

enum MatchDecision { merge, review, distinct }

enum MatchReason { score, sharedIdentifier, conflictingIdentifier, incompatibleKinds, sameSource }

enum IdentifierKind { osm, wikidata, phone, website }

@immutable
final class MatchScore {
  const new({
    required this.score,
    required this.decision,
    required this.reason,
    required this.distanceM,
    required this.distance,
    required this.name,
    required this.kind,
    required this.base,
    this.municipality,
    this.sharedIdentifier,
    this.conflictingIdentifier,
  });

  final double score;
  final MatchDecision decision;
  final MatchReason reason;
  final double distanceM;
  final double distance;
  final double name;
  final double kind;
  final double? municipality;
  final double base;
  final IdentifierKind? sharedIdentifier;
  final IdentifierKind? conflictingIdentifier;
}

/// A record prepared for matching: its comparable values normalised once.
@immutable
final class MatchCandidate {
  factory prepare({
    required String source,
    required PlaceKind kind,
    required LatLng position,
    double accuracyM = 0,
    String? name,
    String? osm,
    String? wikidata,
    String? phone,
    String? website,
    String? cityCode,
    String? postcode,
  }) {
    final folded = name == null ? null : Conflation.fold(name);
    final hasName = folded != null && folded.isNotEmpty;
    final core = hasName ? Conflation.coreTokens(folded) : const <String>[];
    String? clean(String? s) {
      final t = s?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return MatchCandidate._(
      source: source,
      kind: kind,
      position: position,
      accuracyM: accuracyM.isFinite ? accuracyM.clamp(0, Conflation.accuracyCapM).toDouble() : 0,
      folded: hasName ? folded : null,
      foldedTokens: hasName
          ? (folded.split(' ').where((t) => t.isNotEmpty).toSet().toList()..sort())
          : const [],
      foldedTrigrams: hasName ? Conflation.trigrams(folded) : const [],
      coreTokens: core.toSet().toList()..sort(),
      coreTrigrams: hasName ? Conflation.trigrams(core.join(' ')) : const [],
      osm: clean(osm),
      wikidata: wikidata == null ? null : Conflation.normalizeWikidata(wikidata),
      phone: phone == null ? null : Conflation.normalizePhone(phone),
      website: website == null ? null : Conflation.normalizeWebsite(website),
      cityCode: clean(cityCode),
      postcode: clean(postcode),
    );
  }

  const new _({
    required this.source,
    required this.kind,
    required this.position,
    required this.accuracyM,
    required this.folded,
    required this.foldedTokens,
    required this.foldedTrigrams,
    required this.coreTokens,
    required this.coreTrigrams,
    required this.osm,
    required this.wikidata,
    required this.phone,
    required this.website,
    required this.cityCode,
    required this.postcode,
  });

  final String source;
  final PlaceKind kind;
  final LatLng position;
  final double accuracyM;
  final String? folded;
  final List<String> foldedTokens;
  final List<String> foldedTrigrams;
  final List<String> coreTokens;
  final List<String> coreTrigrams;
  final String? osm;
  final String? wikidata;
  final String? phone;
  final String? website;
  final String? cityCode;
  final String? postcode;
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/osrm_shape.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

final _log = Logger('guidance');

/// One page of the API's `enforcement` delta.
@immutable
final class EnforcementPage {
  const new({
    required this.cursor,
    required this.full,
    required this.rules,
    required this.upserts,
    required this.removals,
    required this.sources,
    required this.pollInterval,
    required this.hasMore,
  });

  final String cursor;

  /// [upserts] is the whole set: what is held is replaced.
  final bool full;
  final EnforcementRules rules;
  final List<EnforcementItem> upserts;
  final List<String> removals;
  final List<EnforcementSource> sources;
  final Duration pollInterval;
  final bool hasMore;
}

/// The items of the countries asked changed since a cursor, the rules of
/// every country and the lists the items come from. No position leaves
/// the device: only the countries of the trip.
final enforcementOperation = GraphQLOperation<EnforcementPage>(
  name: 'Enforcement',
  document: r'''
query Enforcement($since: String, $countries: [String!], $first: Int) {
  enforcement(since: $since, countries: $countries, first: $first) {
    cursor
    full
    rules { version reviewedOn countries { country mode } }
    upserts { id kind category country line lat lon bearingDeg limitKmh sourceIds }
    removals
    sources { id name attribution fetchedAt listUpdatedAt }
    pollIntervalSeconds
    hasMore
  }
}
''',
  parse: (data) => enforcementPageFromJson(data['enforcement'] as Map<String, dynamic>),
);

EnforcementPage enforcementPageFromJson(Map<String, dynamic> json) => EnforcementPage(
  cursor: json['cursor'] as String,
  full: json['full'] == true,
  rules: rulesFromJson(json['rules']),
  upserts: [
    for (final i in json['upserts'] as List<dynamic>? ?? const [])
      if (i is Map<String, dynamic>) ?itemFromJson(i),
  ],
  removals: [for (final r in json['removals'] as List<dynamic>? ?? const []) '$r'],
  sources: [
    for (final s in json['sources'] as List<dynamic>? ?? const [])
      if (s is Map<String, dynamic>) ?_source(s),
  ],
  pollInterval: Duration(seconds: (json['pollIntervalSeconds'] as num?)?.toInt() ?? 21600),
  hasMore: json['hasMore'] == true,
);

/// The rules table of the API; a mode this app does not know reads as off.
EnforcementRules rulesFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return EnforcementRules.none;
  return EnforcementRules(
    version: (json['version'] as num?)?.toInt() ?? 0,
    reviewedOn: json['reviewedOn'] as String?,
    countries: {
      for (final c in json['countries'] as List<dynamic>? ?? const [])
        if (c is Map<String, dynamic> && c['country'] is String)
          (c['country'] as String).toUpperCase(): EnforcementMode.fromWire(c['mode']),
    },
  );
}

Map<String, Object?> rulesToJson(EnforcementRules rules) => {
  'version': rules.version,
  'reviewedOn': rules.reviewedOn,
  'countries': [
    for (final MapEntry(:key, :value) in rules.countries.entries)
      {'country': key, 'mode': value.wire},
  ],
};

/// An item; null for a kind this app does not know, or one without what
/// its kind needs (a zone without its road, a camera without its point).
EnforcementItem? itemFromJson(Map<String, dynamic> json) {
  final kind = switch (json['kind']) {
    'ZONE' => EnforcementKind.zone,
    'CAMERA' => EnforcementKind.camera,
    _ => null,
  };
  final id = json['id'];
  final country = json['country'];
  if (kind == null || id is! String || country is! String) return null;
  final line = json['line'] is String ? decodePolyline(json['line'] as String) : const <LatLng>[];
  final lat = (json['lat'] as num?)?.toDouble();
  final lon = (json['lon'] as num?)?.toDouble();
  final position = lat == null || lon == null ? null : LatLng(lat, lon);
  if (kind == EnforcementKind.zone && line.length < 2) return null;
  if (kind == EnforcementKind.camera && position == null && line.length < 2) return null;
  return EnforcementItem(
    id: id,
    kind: kind,
    category: '${json['category']}',
    country: country.toUpperCase(),
    line: line,
    position: position,
    bearingDeg: (json['bearingDeg'] as num?)?.toDouble(),
    limitKmh: (json['limitKmh'] as num?)?.toInt(),
    sourceIds: [for (final s in json['sourceIds'] as List<dynamic>? ?? const []) '$s'],
  );
}

EnforcementSource? _source(Map<String, dynamic> json) {
  final fetched = DateTime.tryParse('${json['fetchedAt']}');
  if (json['id'] is! String || fetched == null) return null;
  return EnforcementSource(
    id: json['id'] as String,
    name: '${json['name']}',
    attribution: '${json['attribution']}',
    fetchedAt: fetched.toUtc(),
    listUpdatedAt: DateTime.tryParse('${json['listUpdatedAt']}')?.toUtc(),
  );
}

/// What the device keeps of the delta, beside the items: the cursor, the
/// countries it was asked for, the rules and the lists, and when.
@immutable
final class EnforcementState {
  const new({
    this.cursor,
    this.countries = const {},
    this.rules,
    this.sources = const [],
    this.pollInterval = const Duration(hours: 6),
    this.polledAt,
  });

  final String? cursor;

  /// The countries the cursor is for: another set gets the whole set again.
  final Set<String> countries;

  /// The rules the API sent last; null before the first answer.
  final EnforcementRules? rules;
  final List<EnforcementSource> sources;
  final Duration pollInterval;
  final DateTime? polledAt;
}

/// The speed camera data in the place cache (`enforcement_items`, the
/// state in `device_state`): it outlives a run, so a guidance started
/// without network still knows the zones of its countries.
final class EnforcementStore {
  new(this._db);

  final CacheDatabase _db;

  static const _key = 'enforcement';

  Future<EnforcementState> state() async {
    final row = await (_db.select(
      _db.deviceState,
    )..where((s) => s.id.equals(_key))).getSingleOrNull();
    if (row == null) return const EnforcementState();
    try {
      final json = jsonDecode(row.value) as Map<String, dynamic>;
      return EnforcementState(
        cursor: json['cursor'] as String?,
        countries: {for (final c in json['countries'] as List<dynamic>? ?? const []) '$c'},
        rules: json['rules'] == null ? null : rulesFromJson(json['rules']),
        sources: [
          for (final s in json['sources'] as List<dynamic>? ?? const [])
            if (s is Map<String, dynamic>) ?_source(s),
        ],
        pollInterval: Duration(seconds: (json['pollSeconds'] as num?)?.toInt() ?? 21600),
        polledAt: DateTime.tryParse('${json['polledAt']}'),
      );
    } on Object catch (e) {
      _log.info('enforcement state unreadable, starting over: $e');
      return const EnforcementState();
    }
  }

  /// Writes [page] and the state after it in one transaction, the items
  /// filtered by the page's rules ([EnforcementItem.keptUnder]). A full
  /// answer replaces the items of [countries] only: those of other
  /// countries, kept from earlier trips, serve a trip back there offline.
  /// [at] is when the data became whole, null while pages remain: a run cut
  /// short is then due again at once rather than after the server's rhythm.
  Future<void> apply(EnforcementPage page, Set<String> countries, DateTime? at) =>
      _db.transaction(() async {
        if (page.full) {
          await (_db.delete(_db.enforcementItems)..where((i) => i.country.isIn(countries))).go();
        }
        if (page.removals.isNotEmpty) {
          await (_db.delete(_db.enforcementItems)..where((i) => i.id.isIn(page.removals))).go();
        }
        await _db.batch((batch) {
          // Only what the rules of its country allow is written: zones for
          // France, nothing for a country where the app shows nothing.
          for (final item in page.upserts.where((i) => i.keptUnder(page.rules))) {
            batch.insert(_db.enforcementItems, _row(item), mode: InsertMode.insertOrReplace);
          }
        });
        await _db
            .into(_db.deviceState)
            .insertOnConflictUpdate(
              DeviceStateCompanion.insert(
                id: _key,
                value: jsonEncode({
                  'cursor': page.cursor,
                  'countries': countries.toList()..sort(),
                  'rules': rulesToJson(page.rules),
                  'sources': [
                    for (final s in page.sources)
                      {
                        'id': s.id,
                        'name': s.name,
                        'attribution': s.attribution,
                        'fetchedAt': s.fetchedAt.toIso8601String(),
                        'listUpdatedAt': s.listUpdatedAt?.toIso8601String(),
                      },
                  ],
                  'pollSeconds': page.pollInterval.inSeconds,
                  'polledAt': at?.toUtc().toIso8601String(),
                }),
              ),
            );
      });

  EnforcementItemsCompanion _row(EnforcementItem i) => EnforcementItemsCompanion.insert(
    id: i.id,
    kind: i.kind == EnforcementKind.zone ? 'ZONE' : 'CAMERA',
    category: i.category,
    country: i.country,
    line: Value(i.line.length < 2 ? null : encodePolyline(i.line)),
    lat: Value(i.position?.lat),
    lon: Value(i.position?.lon),
    bearingDeg: Value(i.bearingDeg),
    limitKmh: Value(i.limitKmh),
    sourceIds: Value(jsonEncode(i.sourceIds)),
  );

  /// The items of [countries] held.
  Future<List<EnforcementItem>> items(Set<String> countries) async {
    final rows = await (_db.select(
      _db.enforcementItems,
    )..where((i) => i.country.isIn(countries))).get();
    return [
      for (final r in rows)
        ?itemFromJson({
          'id': r.id,
          'kind': r.kind,
          'category': r.category,
          'country': r.country,
          'line': r.line,
          'lat': r.lat,
          'lon': r.lon,
          'bearingDeg': r.bearingDeg,
          'limitKmh': r.limitKmh,
          'sourceIds': jsonDecode(r.sourceIds),
        }),
    ];
  }
}

/// The speed camera data of a trip, as the guidance needs it.
typedef EnforcementData = ({
  /// The rules the API sent last; null before any answer (the app's own
  /// table then applies).
  EnforcementRules? rules,
  List<EnforcementItem> items,

  /// The lists the items come from, credited with them.
  List<EnforcementSource> sources,

  /// When to ask again.
  Duration pollInterval,

  /// When the data was last brought up to date; null when never.
  DateTime? polledAt,
});

/// Where the guidance gets the speed camera data of its countries.
abstract interface class EnforcementFeed {
  /// Brings the data of [countries] up to date when it is due, and answers
  /// what the device holds for them; never fails (offline, the data kept
  /// from earlier serves).
  Future<EnforcementData> refresh(Set<String> countries, DateTime now);
}

/// Keeps the speed camera data of the trip's countries: asks the delta
/// from the stored cursor (the whole set when the countries change), page
/// after page, at most every [EnforcementState.pollInterval] unless the
/// countries grew. Against an API without it, nothing is kept and the
/// guidance shows no zone.
final class EnforcementSync implements EnforcementFeed {
  new({required this.client, required this.store, this.maxPages = 20});

  final GraphQLClient client;
  final EnforcementStore store;
  final int maxPages;

  /// The API answered that it does not know the delta.
  bool _unknown = false;

  /// Polls when due for [countries] at [now]; answers the state after it
  /// (the stored one when nothing was asked or the request failed). Only
  /// the countries of the current route are asked, so the server never
  /// sees the countries of earlier trips; their items stay on the device.
  Future<EnforcementState> poll(Set<String> countries, DateTime now) async {
    final state = await store.state();
    final wanted = {for (final c in countries) c.toUpperCase()};
    final same = state.countries.length == wanted.length && state.countries.containsAll(wanted);
    final due =
        state.polledAt == null || !now.isBefore(state.polledAt!.add(state.pollInterval)) || !same;
    if (_unknown || !due || wanted.isEmpty) return state;
    // The cursor belongs to the countries it was asked with: other
    // countries start from the whole set. One the server no longer reads
    // is dropped once.
    var since = same ? state.cursor : null;
    var dropped = false;
    try {
      for (var page = 0; page < maxPages; page++) {
        final EnforcementPage delta;
        try {
          delta = await client.execute(enforcementOperation, {
            'since': since,
            'countries': wanted.toList()..sort(),
            'first': 1000,
          });
        } on GraphQLResponseException catch (e) {
          if (since == null ||
              dropped ||
              !e.hasCode(GraphQLError.invalidInput) ||
              e.errors.any((error) => error.unknownField)) {
            rethrow;
          }
          since = null;
          dropped = true;
          continue;
        }
        final last = !delta.hasMore || delta.cursor == since;
        await store.apply(delta, wanted, last ? now : null);
        if (last) break;
        since = delta.cursor;
      }
    } on GraphQLResponseException catch (e) {
      if (e.errors.any((error) => error.unknownField)) {
        _unknown = true;
        _log.info('the API has no speed camera data yet');
      } else {
        _log.info('enforcement poll refused: $e');
      }
    } on Object catch (e) {
      // Offline, or an answer this app cannot read: the data kept serves.
      _log.fine('enforcement poll failed: $e');
    }
    return await store.state();
  }

  @override
  Future<EnforcementData> refresh(Set<String> countries, DateTime now) async {
    final state = await poll(countries, now);
    final items = await store.items({for (final c in countries) c.toUpperCase()});
    return (
      rules: state.rules,
      items: items,
      sources: state.sources,
      pollInterval: state.pollInterval,
      polledAt: state.polledAt,
    );
  }
}

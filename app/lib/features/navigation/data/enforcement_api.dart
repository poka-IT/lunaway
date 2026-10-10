import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show setEquals;
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
/// the device: only the countries of the trip, and among them those where
/// the user asked for the cameras' positions (`exactIn`).
final enforcementOperation = GraphQLOperation<EnforcementPage>(
  name: 'Enforcement',
  document: _enforcementDocument,
  // An API older than the choice: the countries' default forms, and rules
  // that do not say which choice exists (optInFallback stands for them).
  older: OlderForm(
    document: _enforcementDocument
        .replaceAll(r', $exactIn: [String!]', '')
        .replaceAll(r', exactIn: $exactIn', '')
        .replaceAll(' optInMode', ''),
    variables: (v) => {
      for (final MapEntry(:key, :value) in v.entries)
        if (key != 'exactIn') key: value,
    },
    withoutFields: true,
  ),
  parse: (data) => enforcementPageFromJson(data['enforcement'] as Map<String, dynamic>),
);

const _enforcementDocument = r'''
query Enforcement($since: String, $countries: [String!], $first: Int, $exactIn: [String!]) {
  enforcement(since: $since, countries: $countries, first: $first, exactIn: $exactIn) {
    cursor
    full
    rules { version reviewedOn countries { country mode optInMode } }
    upserts { id kind category country line lat lon bearingDeg limitKmh sourceIds }
    removals
    sources { id name attribution fetchedAt listUpdatedAt }
    pollIntervalSeconds
    hasMore
  }
}
''';

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
/// The choices (`optInMode`) are known only from a table that carries the
/// field: an older one leaves them to [optInFallback].
EnforcementRules rulesFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return EnforcementRules.none;
  final lines = [
    for (final c in json['countries'] as List<dynamic>? ?? const [])
      if (c is Map<String, dynamic> && c['country'] is String) c,
  ];
  return EnforcementRules(
    version: (json['version'] as num?)?.toInt() ?? 0,
    reviewedOn: json['reviewedOn'] as String?,
    countries: {
      for (final c in lines)
        (c['country'] as String).toUpperCase(): EnforcementMode.fromWire(c['mode']),
    },
    optIn: lines.any((c) => c.containsKey('optInMode'))
        ? {
            for (final c in lines)
              if (c['optInMode'] != null)
                (c['country'] as String).toUpperCase(): EnforcementMode.fromWire(c['optInMode']),
          }
        : null,
  );
}

Map<String, Object?> rulesToJson(EnforcementRules rules) => {
  'version': rules.version,
  'reviewedOn': rules.reviewedOn,
  'countries': [
    for (final MapEntry(:key, :value) in rules.countries.entries)
      {
        'country': key,
        'mode': value.wire,
        if (rules.optIn case final optIn?) 'optInMode': optIn[key]?.wire,
      },
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
    // Both empty when absent, never the word "null": the banner cites the
    // name, the preview the attribution or else the name.
    name: switch (json['name']) {
      final String n => n,
      _ => '',
    },
    attribution: switch (json['attribution']) {
      final String a => a,
      _ => '',
    },
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
    this.exactIn = const {},
    this.servedUnder = const {},
    this.rules,
    this.sources = const [],
    this.pollInterval = const Duration(hours: 6),
    this.polledAt,
  });

  final String? cursor;

  /// By country, the choice the cameras the device holds of it were served
  /// under, from every trip; a country absent was served without one. The
  /// server sends a neighbour's cameras as points too when they lie within
  /// a kilometre of a country chosen (a Spanish camera at Irun, under
  /// France's choice): their own country's rule cannot tell them apart, so
  /// a withdrawn choice takes every camera of the countries it touched.
  final Map<String, Set<String>> servedUnder;

  /// The countries whose cameras were served under a choice [chosen] does
  /// not hold any more.
  Set<String> taintedFor(Set<String> chosen) => {
    for (final MapEntry(:key, :value) in servedUnder.entries)
      if (!chosen.containsAll(value)) key,
  };

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'countries': countries.toList()..sort(),
    'exactIn': exactIn.toList()..sort(),
    'servedUnder': {
      for (final MapEntry(:key, :value) in servedUnder.entries) key: value.toList()..sort(),
    },
    'rules': rules == null ? null : rulesToJson(rules!),
    'sources': [
      for (final s in sources)
        {
          'id': s.id,
          'name': s.name,
          'attribution': s.attribution,
          'fetchedAt': s.fetchedAt.toIso8601String(),
          'listUpdatedAt': s.listUpdatedAt?.toIso8601String(),
        },
    ],
    'pollSeconds': pollInterval.inSeconds,
    'polledAt': polledAt?.toUtc().toIso8601String(),
  };

  /// The countries the cursor is for: another set gets the whole set again.
  final Set<String> countries;

  /// The countries whose positions were asked with the cursor: another
  /// choice gets the whole set again too.
  final Set<String> exactIn;

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
        exactIn: {for (final c in json['exactIn'] as List<dynamic>? ?? const []) '$c'},
        servedUnder: {
          if (json['servedUnder'] case final Map<String, dynamic> served)
            for (final MapEntry(:key, :value) in served.entries)
              if (value is List) key: {for (final c in value) '$c'},
        },
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
  /// filtered by the page's rules once [exactIn], the choice the page was
  /// asked with, applies ([EnforcementItem.keptUnder] under
  /// [EnforcementRules.withChoices]). A full answer replaces the items of
  /// [countries] only: those of other countries, kept from earlier trips,
  /// serve a trip back there offline. The choice is stored with the cursor,
  /// and with each country's cameras ([EnforcementState.servedUnder]). [at]
  /// is when the data became whole, null while pages remain: a run cut
  /// short is then due again at once rather than after the server's
  /// rhythm.
  Future<void> apply(
    EnforcementPage page,
    Set<String> countries,
    DateTime? at, {
    Set<String> exactIn = const {},
  }) => _db.transaction(() async {
    final before = await state();
    if (page.full) {
      await (_db.delete(_db.enforcementItems)..where((i) => i.country.isIn(countries))).go();
    }
    if (page.removals.isNotEmpty) {
      await (_db.delete(_db.enforcementItems)..where((i) => i.id.isIn(page.removals))).go();
    }
    final rules = page.rules.withChoices(exactIn);
    await _db.batch((batch) {
      // Only what the rules of its country allow is written: zones for
      // France unless the user asked for its positions, nothing for a
      // country where the app shows nothing.
      for (final item in page.upserts.where((i) => i.keptUnder(rules))) {
        batch.insert(_db.enforcementItems, _row(item), mode: InsertMode.insertOrReplace);
      }
    });
    // A whole set replaces what the countries were served under; a page
    // of changes adds to it.
    final served = {...before.servedUnder};
    for (final c in countries) {
      final under = {if (!page.full) ...?served[c], ...exactIn};
      if (under.isEmpty) {
        served.remove(c);
      } else {
        served[c] = under;
      }
    }
    await _write(
      EnforcementState(
        cursor: page.cursor,
        countries: countries,
        exactIn: exactIn,
        servedUnder: served,
        rules: page.rules,
        sources: page.sources,
        pollInterval: page.pollInterval,
        polledAt: at,
      ),
    );
  });

  Future<void> _write(EnforcementState state) => _db
      .into(_db.deviceState)
      .insertOnConflictUpdate(
        DeviceStateCompanion.insert(id: _key, value: jsonEncode(state.toJson())),
      );

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

  /// Removes every item the user's choice [chosen] no longer lets the
  /// device keep, whatever trip it came with: a camera where only zones
  /// may be kept, anything of a country that is off ([EnforcementItem.
  /// keptUnder] under [EnforcementRules.withChoices]), and every camera of
  /// a country served under a choice withdrawn
  /// ([EnforcementState.taintedFor]), its neighbours' included. Those
  /// countries start over from their whole set at the next poll. Run when
  /// the user withdraws a choice, so the positions go from the device at
  /// once, offline too.
  Future<void> dropRefused(Set<String> chosen) => _db.transaction(() async {
    final before = await state();
    final table = before.rules;
    // Nothing was ever kept without a table.
    if (table == null) return;
    final rules = table.withChoices(chosen);
    final tainted = before.taintedFor(chosen);
    final points = [
      for (final MapEntry(:key, :value) in rules.countries.entries)
        if (value == EnforcementMode.exact && !tainted.contains(key)) key,
    ];
    final stretches = [
      for (final MapEntry(:key, :value) in rules.countries.entries)
        if (value.shows) key,
    ];
    await (_db.delete(
      _db.enforcementItems,
    )..where((i) => i.kind.equals('CAMERA') & i.country.isNotIn(points))).go();
    await (_db.delete(
      _db.enforcementItems,
    )..where((i) => i.kind.equals('ZONE') & i.country.isNotIn(stretches))).go();
    if (tainted.isEmpty) return;
    final restart = before.countries.any(tainted.contains);
    await _write(
      EnforcementState(
        // The cursor would only bring changes onto what is gone.
        cursor: restart ? null : before.cursor,
        countries: before.countries,
        exactIn: before.exactIn,
        servedUnder: {
          for (final MapEntry(:key, :value) in before.servedUnder.entries)
            if (!tainted.contains(key)) key: value,
        },
        rules: table,
        sources: before.sources,
        pollInterval: before.pollInterval,
        polledAt: restart ? null : before.polledAt,
      ),
    );
  });

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
  /// from earlier serves). The rules answered are the table as received:
  /// the user's choices apply on top ([EnforcementRules.withChoices]).
  Future<EnforcementData> refresh(Set<String> countries, DateTime now);

  /// Removes from the device what the user's choices no longer allow: the
  /// positions of a country whose choice was withdrawn, from every trip.
  Future<void> purge();
}

/// No choice made: the default of every country.
Future<Set<String>> _noChoice() async => const {};

/// Keeps the speed camera data of the trip's countries: asks the delta
/// from the stored cursor (the whole set when the countries or the choices
/// change), page after page, at most every [EnforcementState.pollInterval]
/// unless the countries grew. Against an API without it, nothing is kept
/// and the guidance shows no zone.
final class EnforcementSync implements EnforcementFeed {
  new({required this.client, required this.store, this.chosen = _noChoice, this.maxPages = 20});

  final GraphQLClient client;
  final EnforcementStore store;

  /// The countries where the user asked for the cameras' positions
  /// (`DrivingAidsSettings.exactIn`), read at each poll and each purge.
  /// Never logged.
  final Future<Set<String>> Function() chosen;
  final int maxPages;

  /// The API answered that it does not know the delta.
  bool _unknown = false;

  /// The poll running: the preview and the guidance both ask, and their
  /// pages must not interleave in the store.
  Future<void> _running = Future.value();

  /// Polls when due for [countries] at [now]; answers the state after it
  /// (the stored one when nothing was asked or the request failed). Only
  /// the countries of the current route are asked, so the server never
  /// sees the countries of earlier trips; their items stay on the device.
  Future<EnforcementState> poll(Set<String> countries, DateTime now) {
    final run = _running.then((_) => _poll(countries, now));
    _running = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<EnforcementState> _poll(Set<String> countries, DateTime now) async {
    final state = await store.state();
    final wanted = {for (final c in countries) c.toUpperCase()};
    // A choice says something only of the countries of this trip: a trip
    // in Spain does not tell the server what was chosen for France.
    final exact = await _chosenAmong(wanted);
    final same = setEquals(state.countries, wanted) && setEquals(state.exactIn, exact);
    final due =
        state.polledAt == null || !now.isBefore(state.polledAt!.add(state.pollInterval)) || !same;
    if (_unknown || !due || wanted.isEmpty) return state;
    // The cursor belongs to the countries and the choices it was asked
    // with: others start from the whole set. One the server no longer
    // reads is dropped once.
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
            if (exact.isNotEmpty) 'exactIn': exact.toList()..sort(),
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
        // A choice changed while the page came: the page belongs to the
        // old one, and the next poll asks the whole set under the new.
        if (!setEquals(await _chosenAmong(wanted), exact)) break;
        final last = !delta.hasMore || delta.cursor == since;
        await store.apply(delta, wanted, last ? now : null, exactIn: exact);
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

  /// The user's choice; none when the settings cannot be read, the strict
  /// side: the feed never fails for them.
  Future<Set<String>> _choice() async {
    try {
      return await chosen();
    } on Object {
      return const {};
    }
  }

  /// The countries of [wanted] the user asked the positions of.
  Future<Set<String>> _chosenAmong(Set<String> wanted) async => {
    for (final c in await _choice())
      if (wanted.contains(c.toUpperCase())) c.toUpperCase(),
  };

  @override
  Future<EnforcementData> refresh(Set<String> countries, DateTime now) async {
    final wanted = {for (final c in countries) c.toUpperCase()};
    final state = await poll(wanted, now);
    final items = await store.items(wanted);
    // What the choices no longer allow never leaves the store, even kept
    // by a purge that did not run: no camera of a country served under a
    // choice withdrawn, until its whole set is read again.
    final chosen = await _choice();
    final rules = state.rules?.withChoices(chosen);
    final tainted = state.taintedFor(chosen);
    return (
      rules: state.rules,
      items: [
        for (final i in items)
          if ((rules == null || i.keptUnder(rules)) &&
              !(i.kind == EnforcementKind.camera && tainted.contains(i.country)))
            i,
      ],
      sources: state.sources,
      pollInterval: state.pollInterval,
      polledAt: state.polledAt,
    );
  }

  @override
  Future<void> purge() {
    final run = _running.then((_) => _purge());
    _running = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Runs after any poll in flight, whose pages would otherwise write
  /// back what this removes.
  Future<void> _purge() async => await store.dropRefused(await _choice());
}

import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/favorites/data/home_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';

/// The API does not know the home yet: the device keeps its own, unsent.
final class HomeUnsupported implements Exception {
  const new();

  @override
  String toString() => 'HomeUnsupported';
}

/// The account's home on the server.
abstract interface class HomeRemote {
  /// The account's home; null when it has none. Throws [HomeUnsupported]
  /// for an API older than the home.
  Future<SavedPoint?> home();

  /// Stores [point] as the account's home and returns it as stored; null
  /// when the server refuses its content.
  Future<SavedPoint?> set(SavedPoint point);

  /// Removes the account's home; one already gone is removed.
  Future<void> clear();
}

/// Keeps the device's home and the account's in step, against the state
/// the last sync left (the `home_sync_base` row of `settings`, the home's
/// fingerprint, empty for "no home"):
///
/// - changed here since the last sync (set, changed or removed), the
///   device's goes to the account;
/// - else changed on the account (another device), the account's comes
///   here;
/// - with no last sync (this account's first on the device, or the device
///   changed accounts), the account's home wins when it has one, else the
///   device's goes to it;
/// - a home the server refused stays here unsent until it changes here.
///
/// The home is private: nothing here logs its name, address or position.
final class HomeSync {
  new({required this.db, required this.home, required this.remote});

  final UserDatabase db;
  final HomeRepository home;
  final HomeRemote remote;

  static const String _base = DriftHomeRepository.baseSetting;
  static const String _refused = DriftHomeRepository.refusedSetting;

  /// Forgets what the last sync agreed on: the next one is the first of
  /// whichever account the device holds then. The home stays.
  static Future<void> forgetBase(UserDatabase db) =>
      (db.delete(db.settings)..where((r) => r.id.isIn(const [_base, _refused]))).go();

  Future<void> sync() async {
    final SavedPoint? there;
    try {
      there = await remote.home();
    } on HomeUnsupported {
      return;
    }
    final here = await home.read();
    final base = await _read(_base);
    final hereFp = here?.fingerprint ?? '';
    final thereFp = there?.fingerprint ?? '';
    if (here != null && await _read(_refused) == hereFp) return;
    if (base == null) {
      if (there != null) return await _take(there);
      if (here != null) return await _push(here);
      return await _write(_base, '');
    }
    if (hereFp != base) {
      if (here == null) {
        await remote.clear();
        return await _write(_base, '');
      }
      return await _push(here);
    }
    if (thereFp != base) await _take(there);
  }

  Future<void> _push(SavedPoint here) async {
    final stored = await remote.set(here);
    if (stored == null) return await _write(_refused, here.fingerprint);
    await _drop(_refused);
    // The server folds a text as the app does: a difference is one the
    // device learns, never one it sends back.
    if (stored.fingerprint != here.fingerprint) await home.set(stored);
    await _write(_base, stored.fingerprint);
  }

  Future<void> _take(SavedPoint? there) async {
    if (there == null) {
      await home.clear();
    } else {
      await home.set(there);
    }
    await _drop(_refused);
    await _write(_base, there?.fingerprint ?? '');
  }

  Future<String?> _read(String id) async =>
      (await (db.select(db.settings)..where((r) => r.id.equals(id))).getSingleOrNull())?.value;

  Future<void> _write(String id, String value) =>
      db.into(db.settings).insertOnConflictUpdate(SettingsCompanion.insert(id: id, value: value));

  Future<void> _drop(String id) => (db.delete(db.settings)..where((r) => r.id.equals(id))).go();
}

/// The account's home through the API.
final class GraphQLHomeRemote implements HomeRemote {
  new(this.account);

  final AccountService account;

  static const _fields = 'kind name address lat lon poiId poiKind';

  static SavedPoint? _home(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return asHome(
      SavedPoint(
        id: '',
        kind: SavedPointKind.fromWire(json['kind']),
        name: json['name'] as String,
        position: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
        address: json['address'] as String?,
        poiId: json['poiId'] as String?,
        poiKindCode: (json['poiKind'] as String?)?.toLowerCase(),
      ),
    );
  }

  /// [point] as `HomeInput`.
  static Map<String, Object?> input(SavedPoint point) => {
    'kind': point.kind.wire,
    'name': point.name,
    'address': ?point.address,
    'lat': point.position.lat,
    'lon': point.position.lon,
    if (point.kind == SavedPointKind.poi) ...{
      'poiId': ?point.poiId,
      'poiKind': ?point.poiKindCode?.toUpperCase(),
    },
  };

  static final homeOperation = GraphQLOperation<SavedPoint?>(
    name: 'MyHome',
    document: 'query MyHome { myHome { $_fields } }',
    parse: (data) => _home(data['myHome']),
  );

  static final setOperation = GraphQLOperation<SavedPoint?>(
    name: 'SetHome',
    document: 'mutation SetHome(\$home: HomeInput!) { setHome(home: \$home) { $_fields } }',
    parse: (data) => _home(data['setHome']),
  );

  static final clearOperation = GraphQLOperation<bool>(
    name: 'ClearHome',
    document: 'mutation ClearHome { clearHome }',
    parse: (data) => data['clearHome'] == true,
  );

  static final operations = <GraphQLOperation<Object?>>[
    homeOperation,
    setOperation,
    clearOperation,
  ];

  @override
  Future<SavedPoint?> home() async {
    try {
      return await account.run(homeOperation);
    } on GraphQLResponseException catch (e) {
      if (e.errors.any((x) => x.unknownField)) throw const HomeUnsupported();
      rethrow;
    }
  }

  @override
  Future<SavedPoint?> set(SavedPoint point) async {
    try {
      return await account.run(setOperation, variables: {'home': input(point)});
    } on GraphQLResponseException catch (e) {
      // Its content: sending it again would be refused again.
      if (e.errors.any(
        (x) => x.code == GraphQLError.invalidInput && !x.unknownField && !x.unknownInput,
      )) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> clear() => account.run(clearOperation);
}

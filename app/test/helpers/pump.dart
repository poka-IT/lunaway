import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show IconButton, TextButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunaway/app.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/pending_files.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/presentation/locate_button.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/places/application/place_digests.dart';
import 'package:lunaway/features/places/application/place_external_providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/demo/demo_server.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/features/regions/domain/regions.dart';
import 'package:lunaway/i18n/strings.g.dart';

import 'fake_api.dart';
import 'fakes.dart';
import 'poi_fakes.dart';
import 'samples.dart';

const phone = Size(400, 860);
const tablet = Size(720, 1000);
const desktop = Size(1280, 820);

/// Settings kept in memory, recording every save.
final class MemorySettings implements SettingsStore {
  new([this.value = const AppSettings()]);

  AppSettings value;
  int saves = 0;

  @override
  Future<AppSettings> load() async => value;

  @override
  Future<void> save(AppSettings settings) async {
    saves++;
    value = settings;
  }
}

/// A sync source that pages through [places] in memory.
final class FakeChangesSource implements ChangesSource {
  new(this.places, {this.failing = false});

  final List<Place> places;
  bool failing;

  /// Pages asked for, failed ones included.
  int requests = 0;

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    requests++;
    if (failing) throw GraphQLNetworkException('offline', null);
    final start = int.tryParse(since ?? '') ?? 0;
    final end = (start + first).clamp(0, places.length);
    return ChangeSet(
      places: places.sublist(start, end),
      deleted: const [],
      cursor: '$end',
      hasMore: end < places.length,
    );
  }
}

/// Everything a widget test of the app wires: the fakes it can inspect.
final class TestApp {
  new({
    required this.places,
    required this.favorites,
    required this.external,
    required this.map,
    required this.settings,
    required this.extras,
    required this.externalSource,
    required this.digests,
    required this.cache,
    required this.user,
    required this.location,
    required this.secrets,
    required this.files,
    this.api,
    this.online,
  });

  final FakePlacesRepository places;
  final FakeFavoritesRepository favorites;
  final FakeExternalActions external;
  final FakeMap map;
  final MemorySettings settings;
  final FakeExtrasSource extras;

  /// The external community source; nothing from it by default.
  final FakeExternalSource externalSource;

  /// The digests of the lists' rows; none by default.
  final FakeDigestSource digests;
  final CacheDatabase cache;
  final UserDatabase user;
  final FakeLocationPermissions location;
  final MemorySecretStore secrets;
  final MemoryPendingFiles files;

  /// The account and community API, when the test talks to one.
  final FakeApi? api;

  /// The API's places, when the map draws them from the tiles.
  final FakeOnlinePlaces? online;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
}

/// An in-memory database whose query streams stop at once when their last
/// listener goes: drift otherwise stops them on a timer, which outlives the
/// widget tree of a test.
DatabaseConnection memoryDatabase() =>
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true);

/// Pumps the whole app at [size] with fakes around it: no network, no disk,
/// a fixed clock ([testNow]) that does not tick, and a fake map. The theme
/// follows [brightness] (the app's own setting, not the system's).
Future<TestApp> pumpLunaway(
  WidgetTester tester, {
  Size size = phone,
  // The system's bars (status, gestures), in physical pixels.
  FakeViewPadding? viewPadding,
  List<Place>? places,
  AppLocale locale = AppLocale.fr,
  AppSettings? settings,
  SyncState? sync,
  bool neverSynced = false,
  Brightness brightness = Brightness.light,
  FakeExtrasSource? extras,
  FakeExternalSource? external,
  FakeDigestSource? digests,
  SyncService? syncService,
  FakeMap? map,
  double textScale = 1,
  bool settle = true,
  BasemapTemplates basemap = BasemapTemplates.blank,
  AppConfig? config,
  FakeApi? api,
  bool signedIn = false,
  // When the signed-in account's recovery card was made, on the server and
  // on the device; none by default.
  DateTime? recoveryCardAt,
  FakePoiSource? pois,
  MemoryPackFiles? packFiles,
  bool? reachable = true,
  http.Client? httpClient,
  // The regions the API offers; null for an API without regions (the sync
  // by box of [syncService] runs).
  RegionCatalog? regions,
  // What the device's location permission says from the start.
  LocationAccess locationAccess = LocationAccess.granted,
  // More fakes, for a feature's own providers (the navigation's).
  List<Override> overrides = const [],
  // The app's clock and its minutes, for a test that moves time on; the
  // fixed [testNow] and no minute by default.
  DateTime Function()? clock,
  MinuteTicker? minuteTicker,
  // Whether the system shows what was copied (Android 13 and later).
  bool systemShowsCopies = false,
  // The places come from the API's tiles and queries, as on the web and on a
  // phone online; null keeps them on the device, as offline.
  FakeOnlinePlaces? online,
  // How long the first sync waits behind the map; at once by default, so the
  // tests of the download see it start.
  ({Duration afterMap, Duration atLatest}) syncStartDelays = (
    afterMap: Duration.zero,
    atLatest: Duration.zero,
  ),
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (viewPadding != null) {
    tester.view.padding = viewPadding;
    tester.view.viewPadding = viewPadding;
  }
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // The app's own channel to the system answers as Android would; unanswered,
  // a call would never end in a test.
  const system = MethodChannel('lunaway/system');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    system,
    (call) async => call.method == 'showsCopies' && systemShowsCopies,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(system, null));
  await LocaleSettings.setLocale(locale);
  final initial =
      settings ??
      AppSettings(
        theme: brightness == Brightness.dark ? ThemePreference.dark : ThemePreference.light,
      );

  final app = TestApp(
    places: FakePlacesRepository(
      places ?? samplePlaces,
      sync:
          sync ??
          (neverSynced
              ? SyncState.none
              : SyncState(cursor: 'c', completedAt: testNow.subtract(const Duration(hours: 1)))),
    ),
    favorites: FakeFavoritesRepository(),
    external: FakeExternalActions(),
    map: map ?? FakeMap(),
    settings: MemorySettings(initial),
    extras: extras ?? FakeExtrasSource(photos: samplePhotos, reviews: sampleReviews),
    externalSource: external ?? FakeExternalSource(),
    digests: digests ?? FakeDigestSource(),
    cache: CacheDatabase(memoryDatabase()),
    user: UserDatabase(memoryDatabase()),
    location: FakeLocationPermissions()..current = locationAccess,
    secrets: MemorySecretStore(),
    files: MemoryPendingFiles(),
    api: api,
    online: online,
  );
  if (api != null) {
    addTearDown(() => expect(api.violations, isEmpty, reason: 'the API schema'));
    if (signedIn) await seedAccount(app.secrets, api);
    if (signedIn && recoveryCardAt != null) {
      await app.secrets.write('recovery_card', recoveryCardAt.toIso8601String());
      api.recoveryCodeCreatedAt ??= recoveryCardAt;
    }
  }
  // The in-memory databases are left to the garbage collector: closing one
  // waits for its queries, and a query the failed test left pending under
  // the fake clock never ends, which would hang the whole run.

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        placesRepositoryProvider.overrideWithValue(app.places),
        favoritesRepositoryProvider.overrideWithValue(app.favorites),
        externalActionsProvider.overrideWithValue(app.external),
        lunaMapBuilderProvider.overrideWithValue(app.map.build),
        basemapTemplatesProvider.overrideWithValue(basemap),
        if (config != null) appConfigProvider.overrideWithValue(config),
        clockProvider.overrideWithValue(clock ?? () => testNow),
        minuteTickerProvider.overrideWithValue(minuteTicker ?? (_) => const Stream.empty()),
        settingsRepositoryProvider.overrideWithValue(app.settings),
        initialSettingsProvider.overrideWithValue(initial),
        cacheDatabaseProvider.overrideWithValue(app.cache),
        userDatabaseProvider.overrideWithValue(app.user),
        locationPermissionsProvider.overrideWithValue(app.location),
        syncRetryDelaysProvider.overrideWithValue(const []),
        syncStartDelaysProvider.overrideWithValue(syncStartDelays),
        // The account's secrets in memory: no keychain in a widget test.
        secretStoreProvider.overrideWithValue(app.secrets),
        pendingFilesProvider.overrideWithValue(app.files),
        // Photos come from the demo server, drawn in process: no network.
        httpClientProvider.overrideWithValue(httpClient ?? api?.client(_demo) ?? _demo),
        placeExtrasRepositoryProvider.overrideWithValue(
          PlaceExtrasRepository(db: app.cache, source: app.extras, clock: () => testNow),
        ),
        placeExternalSourceProvider.overrideWithValue(app.externalSource),
        placeDigestSourceProvider.overrideWithValue(app.digests),
        syncServiceProvider.overrideWithValue(
          syncService ?? SyncService(source: FakeChangesSource(const []), store: _NoStore()),
        ),
        // The points of interest in memory, the basemap's host answering
        // (or not, as the test says), the offline maps' folder in memory.
        poiRepositoryProvider.overrideWithValue(
          PoiRepository(db: app.cache, source: pois ?? FakePoiSource(), clock: () => testNow),
        ),
        basemapReachabilityProvider.overrideWith(() => FixedReachability(reachable: reachable)),
        packFilesProvider.overrideWithValue(packFiles ?? MemoryPackFiles()),
        regionCatalogControllerProvider.overrideWith(() => FixedRegionCatalog(regions)),
        deviceCountryProvider.overrideWithValue('FR'),
        placesFromTilesProvider.overrideWithValue(online != null),
        if (online != null) onlinePlacesProvider.overrideWithValue(online),
        ...overrides,
      ],
      child: TranslationProvider(child: const LunawayApp()),
    ),
  );
  if (settle) await settleShort(tester);
  return app;
}

/// The demo server the tests talk to by default, for a fake that answers a
/// few operations of its own and hands it the others.
http.Client get testDemoClient => _demo;

final http.Client _demo = demoApiClient(
  const [],
  apiBase: Uri.parse(testApiBase),
  latency: Duration.zero,
);

/// A device that already holds an account of [api]: its key, the account
/// and a session, as a sign-in would have left them.
Future<void> seedAccount(MemorySecretStore secrets, FakeApi api) async {
  final key = SoftwareDeviceKey(BigInt.parse('1234567890abcdef1234567890abcdef', radix: 16));
  api.addSession('seeded', key.publicJwk.thumbprint);
  await secrets.write('device_key', key.toStored());
  await secrets.write('account', jsonEncode(api.account()));
  await secrets.write(
    'session',
    Session(
      token: 'seeded',
      expiresAt: testNow.add(const Duration(days: 30)),
      openedAt: testNow.subtract(const Duration(hours: 1)),
    ).toStored(),
  );
}

/// Lets streams, futures and short animations finish; skeletons pulse for
/// ever, so this pumps for a while rather than waiting to settle.
Future<void> settleShort(
  WidgetTester tester, [
  Duration total = const Duration(milliseconds: 900),
]) async {
  for (var waited = Duration.zero; waited < total; waited += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _NoStore implements SyncStore {
  @override
  Future<SyncState> stateOf(String region) async =>
      SyncState(cursor: 'c', completedAt: DateTime.utc(2026));

  @override
  Future<void> beginFullSync(String region) async {}

  @override
  Future<void> beginDeltaSync(String region) async {}

  @override
  Future<void> applyPage(String region, ChangeSet page) async {}

  @override
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at) async => 0;

  @override
  Future<void> reset(String region, GeoBounds bounds) async {}
}

/// A sync store in memory that keeps the state the way the drift one does.
final class MemorySyncStore implements SyncStore {
  SyncState state = SyncState.none;

  @override
  Future<SyncState> stateOf(String region) async => state;

  @override
  Future<void> beginFullSync(String region) async =>
      state = SyncState(generation: state.generation + 1, fullSync: true, running: true);

  @override
  Future<void> beginDeltaSync(String region) async => state = SyncState(
    cursor: state.cursor,
    generation: state.generation,
    running: true,
    completedAt: state.completedAt,
  );

  @override
  Future<void> applyPage(String region, ChangeSet page) async => state = SyncState(
    cursor: page.cursor,
    generation: state.generation,
    fullSync: state.fullSync,
    running: true,
    completedAt: state.completedAt,
  );

  @override
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at) async {
    state = SyncState(cursor: state.cursor, generation: state.generation, completedAt: at);
    return 0;
  }

  @override
  Future<void> reset(String region, GeoBounds bounds) async => state = SyncState.none;
}

/// The manifest of the regions as a test sets it: never read online.
final class FixedRegionCatalog extends RegionCatalogController {
  new(this.catalog);

  final RegionCatalog? catalog;

  @override
  Future<RegionCatalog?> build() async => catalog;

  @override
  Future<RegionCatalog?> refresh() async => catalog;
}

/// The map's position button: round, or in words at the country's view
/// before the user is located (`LocateButton`).
final Finder locateButton = find.descendant(
  of: find.byType(LocateButton),
  matching: find.byWidgetPredicate((w) => w is IconButton || w is TextButton),
);

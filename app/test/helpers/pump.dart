import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';

import 'fakes.dart';
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

  @override
  Future<ChangeSet> changes({required GeoBounds bbox, required int first, String? since}) async {
    if (failing) throw StateError('offline');
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
    required this.db,
  });

  final FakePlacesRepository places;
  final FakeFavoritesRepository favorites;
  final FakeExternalActions external;
  final FakeMap map;
  final MemorySettings settings;
  final FakeExtrasSource extras;
  final AppDatabase db;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
}

/// Pumps the whole app at [size] with fakes around it: no network, no disk,
/// a fixed clock ([testNow]) and a fake map.
Future<TestApp> pumpLunaway(
  WidgetTester tester, {
  Size size = phone,
  List<Place>? places,
  AppLocale locale = AppLocale.fr,
  AppSettings settings = const AppSettings(filter: PlaceFilter.none),
  DateTime? lastSync,
  bool neverSynced = false,
  Brightness brightness = Brightness.light,
  FakeExtrasSource? extras,
  SyncService? sync,
  FakeMap? map,
  bool settle = true,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await LocaleSettings.setLocale(locale);

  final app = TestApp(
    places: FakePlacesRepository(
      places ?? samplePlaces,
      lastSync: neverSynced ? null : lastSync ?? testNow.subtract(const Duration(hours: 1)),
    ),
    favorites: FakeFavoritesRepository(),
    external: FakeExternalActions(),
    map: map ?? FakeMap(),
    settings: MemorySettings(settings),
    extras: extras ?? FakeExtrasSource(photos: samplePhotos, reviews: sampleReviews),
    db: AppDatabase(NativeDatabase.memory()),
  );
  addTearDown(app.db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        placesRepositoryProvider.overrideWithValue(app.places),
        favoritesRepositoryProvider.overrideWithValue(app.favorites),
        externalActionsProvider.overrideWithValue(app.external),
        lunaMapBuilderProvider.overrideWithValue(app.map.build),
        clockProvider.overrideWithValue(() => testNow),
        settingsRepositoryProvider.overrideWithValue(app.settings),
        initialSettingsProvider.overrideWithValue(settings),
        appDatabaseProvider.overrideWithValue(app.db),
        placeExtrasRepositoryProvider.overrideWithValue(
          PlaceExtrasRepository(db: app.db, source: app.extras, clock: () => testNow),
        ),
        syncServiceProvider.overrideWithValue(
          sync ?? SyncService(source: FakeChangesSource(const []), store: _NoStore()),
        ),
      ],
      child: TranslationProvider(child: const LunawayApp()),
    ),
  );
  if (settle) await settleShort(tester);
  return app;
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
  Future<void> applyPage(String region, ChangeSet page, DateTime syncedAt) async {}

  @override
  Future<String?> cursorFor(String region) async => null;

  @override
  Future<void> reset(String region) async {}

  @override
  Future<DateTime?> fullSyncStart(String region) async => null;

  @override
  Future<void> beginFullSync(String region, DateTime at) async {}

  @override
  Future<int> finishFullSync(String region, GeoBounds bounds) async => 0;
}

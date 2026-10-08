import 'dart:convert';

import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// How the app picks its light or dark look.
enum ThemePreference {
  /// Light by day, dark after sunset at the user's last known position.
  auto,
  light,
  dark;

  static ThemePreference fromName(String? name) => values.asNameMap()[name] ?? ThemePreference.auto;
}

/// The user's choices, kept on the device.
@immutable
final class AppSettings {
  const new({
    this.localeCode,
    this.filter = PlaceFilter.none,
    this.theme = ThemePreference.auto,
    this.navigationApp,
    this.railCollapsed = false,
    this.copyFormat = CoordinateFormat.decimal,
    this.mapTapHintShown = false,
  });

  /// Null: follow the device language.
  final String? localeCode;

  /// The last filters, so a choice made once stays made.
  final PlaceFilter filter;

  final ThemePreference theme;

  /// The navigation app the user picked for directions, by its id; null
  /// until a first choice, which the chooser then offers to remember.
  final String? navigationApp;

  /// The desktop rail shows its icons only, the labels folded away.
  final bool railCollapsed;

  /// What the "Copy" of a position copies: the last format picked from the
  /// coordinates' menu, so a user who pastes into one tool every day picks
  /// it once.
  final CoordinateFormat copyFormat;

  /// The one line saying that a tap on the map at street level leads
  /// somewhere was shown: it never comes back.
  final bool mapTapHintShown;

  AppSettings copyWith({
    String? Function()? localeCode,
    PlaceFilter? filter,
    ThemePreference? theme,
    String? Function()? navigationApp,
    bool? railCollapsed,
    CoordinateFormat? copyFormat,
    bool? mapTapHintShown,
  }) => AppSettings(
    localeCode: localeCode == null ? this.localeCode : localeCode(),
    filter: filter ?? this.filter,
    theme: theme ?? this.theme,
    navigationApp: navigationApp == null ? this.navigationApp : navigationApp(),
    railCollapsed: railCollapsed ?? this.railCollapsed,
    copyFormat: copyFormat ?? this.copyFormat,
    mapTapHintShown: mapTapHintShown ?? this.mapTapHintShown,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.localeCode == localeCode &&
      other.filter == filter &&
      other.theme == theme &&
      other.navigationApp == navigationApp &&
      other.railCollapsed == railCollapsed &&
      other.copyFormat == copyFormat &&
      other.mapTapHintShown == mapTapHintShown;

  @override
  int get hashCode => Object.hash(
    localeCode,
    filter,
    theme,
    navigationApp,
    railCollapsed,
    copyFormat,
    mapTapHintShown,
  );
}

/// Where the settings live between runs.
abstract interface class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// Key-value storage of [AppSettings] in the `settings` table.
final class SettingsRepository implements SettingsStore {
  new(this._db);

  final UserDatabase _db;

  static const _locale = 'locale';
  static const _filter = 'filter';
  static const _theme = 'theme';
  static const _navigation = 'navigation_app';
  static const _rail = 'rail_collapsed';
  static const _copyFormat = 'copy_format';
  static const _mapTapHint = 'map_tap_hint_shown';

  @override
  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settings).get();
    final values = {for (final r in rows) r.id: r.value};
    return AppSettings(
      localeCode: values[_locale],
      filter: decodeFilter(values[_filter]),
      theme: ThemePreference.fromName(values[_theme]),
      navigationApp: values[_navigation],
      railCollapsed: values[_rail] == 'true',
      // A format an older or newer app wrote and this one lacks copies the
      // default.
      copyFormat: CoordinateFormat.values.asNameMap()[values[_copyFormat]] ?? .decimal,
      mapTapHintShown: values[_mapTapHint] == 'true',
    );
  }

  @override
  Future<void> save(AppSettings settings) => _db.transaction(() async {
    await _putOrDelete(_locale, settings.localeCode);
    await _putOrDelete(_navigation, settings.navigationApp);
    await _put(_filter, jsonEncode(encodeFilter(settings.filter)));
    await _put(_theme, settings.theme.name);
    await _put(_rail, '${settings.railCollapsed}');
    await _put(_copyFormat, settings.copyFormat.name);
    await _put(_mapTapHint, '${settings.mapTapHintShown}');
  });

  Future<void> _putOrDelete(String id, String? value) async {
    if (value == null) {
      await (_db.delete(_db.settings)..where((s) => s.id.equals(id))).go();
    } else {
      await _put(id, value);
    }
  }

  Future<void> _put(String id, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(id: id, value: value));

  @visibleForTesting
  static Map<String, Object?> encodeFilter(PlaceFilter f) => {
    'families': [for (final x in f.families) x.name],
    'overnight': [for (final o in f.overnight) o.name],
    'amenities': [for (final a in f.amenities) a.name],
    'fitsMyVehicle': f.fitsMyVehicle,
    'freeOnly': f.freeOnly,
    'minRating': ?f.minRating,
  };

  /// Unknown names (an older or newer app) are dropped, never fatal.
  @visibleForTesting
  static PlaceFilter decodeFilter(String? raw) {
    if (raw == null) return PlaceFilter.none;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlaceFilter(
        families: {
          for (final n in (json['families'] as List<dynamic>? ?? const []))
            ?KindFamily.values.asNameMap()['$n'],
        },
        overnight: {
          for (final n in (json['overnight'] as List<dynamic>? ?? const []))
            ?OvernightStatus.values.asNameMap()['$n'],
        },
        amenities: {
          for (final n in (json['amenities'] as List<dynamic>? ?? const []))
            // One the filters no longer offer (LPG) is dropped: kept, it would
            // narrow the map with no chip to turn it off.
            ?{for (final a in Amenity.offered) a.name: a}['$n'],
        },
        fitsMyVehicle: json['fitsMyVehicle'] == true,
        freeOnly: json['freeOnly'] == true,
        // A step the filters no longer offer is dropped, as an amenity is.
        minRating: switch (json['minRating']) {
          final num n when minRatingSteps.contains(n.toDouble()) => n.toDouble(),
          _ => null,
        },
      );
      // A corrupt value falls back to no filter rather than blocking startup.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return PlaceFilter.none;
    }
  }
}

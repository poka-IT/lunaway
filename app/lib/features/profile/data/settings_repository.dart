import 'dart:convert';

import 'package:lunaway/core/database/app_database.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// The user's choices, kept on the device.
@immutable
final class AppSettings {
  const new({this.localeCode, this.filter = PlaceFilter.initial});

  /// Null: follow the device language.
  final String? localeCode;

  /// The last filters, so a vehicle height set once stays set.
  final PlaceFilter filter;

  AppSettings copyWith({String? Function()? localeCode, PlaceFilter? filter}) => AppSettings(
    localeCode: localeCode == null ? this.localeCode : localeCode(),
    filter: filter ?? this.filter,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.localeCode == localeCode && other.filter == filter;

  @override
  int get hashCode => Object.hash(localeCode, filter);
}

/// Where the settings live between runs.
abstract interface class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// Key-value storage of [AppSettings] in the `settings` table.
final class SettingsRepository implements SettingsStore {
  new(this._db);

  final AppDatabase _db;

  static const _locale = 'locale';
  static const _filter = 'filter';

  @override
  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settings).get();
    final values = {for (final r in rows) r.id: r.value};
    return AppSettings(localeCode: values[_locale], filter: _decodeFilter(values[_filter]));
  }

  @override
  Future<void> save(AppSettings settings) => _db.transaction(() async {
    final locale = settings.localeCode;
    if (locale == null) {
      await (_db.delete(_db.settings)..where((s) => s.id.equals(_locale))).go();
    } else {
      await _put(_locale, locale);
    }
    await _put(_filter, jsonEncode(_encodeFilter(settings.filter)));
  });

  Future<void> _put(String id, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(id: id, value: value));

  static Map<String, Object?> _encodeFilter(PlaceFilter f) => {
    'families': [for (final x in f.families) x.name],
    'nightOk': f.nightOk,
    'amenities': [for (final a in f.amenities) a.name],
    'vehicleHeightM': f.vehicleHeightM,
  };

  /// Unknown names (an older or newer app) are dropped, never fatal.
  static PlaceFilter _decodeFilter(String? raw) {
    if (raw == null) return PlaceFilter.initial;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlaceFilter(
        families: {
          for (final n in (json['families'] as List<dynamic>? ?? const []))
            ?KindFamily.values.asNameMap()['$n'],
        },
        nightOk: json['nightOk'] == true,
        amenities: {
          for (final n in (json['amenities'] as List<dynamic>? ?? const []))
            ?Amenity.values.asNameMap()['$n'],
        },
        vehicleHeightM: (json['vehicleHeightM'] as num?)?.toDouble(),
      );
      // A corrupt value falls back to no filter rather than blocking startup.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return PlaceFilter.none;
    }
  }
}

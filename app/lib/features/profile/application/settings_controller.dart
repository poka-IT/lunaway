import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

final _log = Logger('settings');

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
SettingsStore settingsRepository(Ref ref) => SettingsRepository(ref.watch(userDatabaseProvider));

/// The settings as read before the first frame, overridden in `main`, so the
/// app never flashes a default language, theme or filter.
// keepAlive: a constant of the run.
@Riverpod(keepAlive: true)
AppSettings initialSettings(Ref ref) => const AppSettings();

/// The user's settings: the state changes at once, the write follows.
// keepAlive: the settings shape every screen for the whole run.
@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> setLocale(AppLocale? locale) async {
    if (locale == null) {
      await LocaleSettings.useDeviceLocale();
    } else {
      await LocaleSettings.setLocale(locale);
    }
    await _update(state.copyWith(localeCode: () => locale?.languageCode));
  }

  Future<void> setFilter(PlaceFilter filter) => _update(state.copyWith(filter: filter));

  Future<void> setTheme(ThemePreference theme) => _update(state.copyWith(theme: theme));

  /// Remembers the navigation app for directions; null forgets it, so the
  /// chooser shows again.
  Future<void> setNavigationApp(String? id) => _update(state.copyWith(navigationApp: () => id));

  /// Folds the desktop rail to its icons, or unfolds it.
  Future<void> setRailCollapsed({required bool collapsed}) =>
      _update(state.copyWith(railCollapsed: collapsed));

  /// Remembers the format the "Copy" of a position copies.
  Future<void> setCopyFormat(CoordinateFormat format) =>
      _update(state.copyWith(copyFormat: format));

  /// Remembers that the hint on tapping the map was shown.
  Future<void> setMapTapHintShown() => _update(state.copyWith(mapTapHintShown: true));

  /// Orders the list beside the map, and keeps the choice.
  Future<void> setListSort(ListSort sort) => _update(state.copyWith(listSort: sort));

  /// Translates the reviews in another language as they show, or leaves
  /// them to a touch.
  Future<void> setAutoTranslateReviews({required bool on}) =>
      _update(state.copyWith(autoTranslateReviews: on));

  Future<void> _update(AppSettings next) async {
    if (!ref.mounted) return;
    state = next;
    try {
      await ref.read(settingsRepositoryProvider).save(next);
    } on Object catch (e, st) {
      // The choice still holds for this run; only its persistence failed.
      _log.warning('could not save the settings', e, st);
    }
  }
}

/// The user's place filter, a slice of the settings. Screens query with
/// `effectiveFilterProvider`, which adds the vehicle's size.
@riverpod
PlaceFilter placeFilter(Ref ref) => ref.watch(settingsProvider.select((s) => s.filter));

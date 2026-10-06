import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

final _log = Logger('settings');

// keepAlive: a repository over the app-wide database.
@Riverpod(keepAlive: true)
SettingsStore settingsRepository(Ref ref) => SettingsRepository(ref.watch(appDatabaseProvider));

/// The settings as read before the first frame, overridden in `main`, so the
/// app never flashes a default language or filter.
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

/// The active place filter, a slice of the settings.
@riverpod
PlaceFilter placeFilter(Ref ref) => ref.watch(settingsProvider.select((s) => s.filter));

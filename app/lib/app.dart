import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/database/cache_pruning.dart';
import 'package:lunaway/core/layout/pointer_input.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/account/data/card_file_io.dart'
    if (dart.library.js_interop) 'package:lunaway/features/account/data/card_file_web.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/profile/application/appearance_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/image_file_cache_web.dart'
    if (dart.library.io) 'package:lunaway/shared/images/image_file_cache.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';

final _log = Logger('app');

class LunawayApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LunawayApp> createState() => _LunawayAppState();
}

class _LunawayAppState extends ConsumerState<LunawayApp> {
  static final ThemeData _light = lunaTheme(Brightness.light);
  static final ThemeData _dark = lunaTheme(Brightness.dark);
  // The desktop look, with a mouse in a window wide enough for the rail.
  static final ThemeData _lightPointer = lunaTheme(Brightness.light, pointer: true);
  static final ThemeData _darkPointer = lunaTheme(Brightness.dark, pointer: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startSyncBehindTheMap();
      // The contributions made offline leave as soon as they can, and the
      // favourites follow the account once there is one. Neither makes an
      // account: browsing never does.
      ref.read(outboxRunnerProvider.notifier).start();
      ref.read(favoritesSyncControllerProvider.notifier).start();
      // A recovery card image left by a run that ended on the card page.
      unawaited(forgetCardFiles());
      // The copies of pages and photos not opened for three months: traces
      // of where the user looked, not needed any more.
      final now = ref.read(clockProvider)();
      unawaited(
        pruneOpenedPages(
          ref.read(cacheDatabaseProvider),
          now,
        ).then((_) => pruneCachedImages(now)).catchError((Object e) {
          _log.info('the old copies were not pruned: $e');
          return 0;
        }),
      );
    });
  }

  Timer? _syncLater;
  Timer? _syncLatest;

  @override
  void dispose() {
    _syncLater?.cancel();
    _syncLatest?.cancel();
    super.dispose();
  }

  /// The sync starts with the app, not with a screen: it resumes a cut
  /// download, refreshes old data, and comes back on every return to the
  /// foreground. It waits until the map has drawn its first view, plus a
  /// few seconds for the tiles of that view: the map draws the places from
  /// the API's tiles meanwhile, and the download (a region's pack, its
  /// import) must not compete with them. A map that never shows (a link to
  /// another tab) starts it later ([syncStartDelaysProvider]).
  void _startSyncBehindTheMap() {
    if (!ref.read(keepsPlacesProvider)) {
      // The web keeps no places: what an earlier version synced into the
      // browser goes, in the database's own worker.
      unawaited(
        ref.read(driftPlacesRepositoryProvider).forgetAll().catchError((Object e) {
          _log.info('the old places were not forgotten: $e');
          return 0;
        }),
      );
      return;
    }
    void start() {
      _syncLater?.cancel();
      _syncLatest?.cancel();
      if (mounted) ref.read(syncControllerProvider.notifier).start();
    }

    final delays = ref.read(syncStartDelaysProvider);
    _syncLatest = Timer(delays.atLatest, start);
    // The first view starts the short wait, once: a map that keeps moving
    // does not put the download off past the latest start.
    ref.listenManual(viewportProvider, (_, view) {
      if (view != null && _syncLater == null && (_syncLatest?.isActive ?? false)) {
        _syncLater = Timer(delays.afterMap, start);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(appBrightnessProvider);
    // The window's size comes from the view, above the app.
    final pointer = pointerDensity(MediaQuery.sizeOf(context));
    return MaterialApp.router(
      onGenerateTitle: (context) => context.t.appTitle,
      routerConfig: ref.watch(routerProvider),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: pointer ? _lightPointer : _light,
      darkTheme: pointer ? _darkPointer : _dark,
      // Light or dark is decided by the app (the user's choice, or the sun),
      // never by the system's own setting.
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      // At sunset the colours turn slowly rather than at once.
      themeAnimationDuration: Motion.pulse,
      debugShowCheckedModeBanner: false,
    );
  }
}

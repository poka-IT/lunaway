import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/profile/application/appearance_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';

class LunawayApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LunawayApp> createState() => _LunawayAppState();
}

class _LunawayAppState extends ConsumerState<LunawayApp> {
  static final ThemeData _light = lunaTheme(Brightness.light);
  static final ThemeData _dark = lunaTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    // The sync starts with the app, not with a screen: it resumes a cut
    // download, refreshes old data, and comes back on every return to the
    // foreground.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncControllerProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(appBrightnessProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.t.appTitle,
      routerConfig: ref.watch(routerProvider),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _light,
      darkTheme: _dark,
      // Light or dark is decided by the app (the user's choice, or the sun),
      // never by the system's own setting.
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      // At sunset the colours turn slowly rather than at once.
      themeAnimationDuration: Motion.pulse,
      debugShowCheckedModeBanner: false,
    );
  }
}

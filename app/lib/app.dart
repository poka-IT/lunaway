import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// Night blue: the colour of a sky above a quiet overnight spot.
const _seed = Color(0xFF1F4E79);

class LunawayApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.t.appTitle,
      routerConfig: ref.watch(routerProvider),
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: _seed),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: .dark),
      debugShowCheckedModeBanner: false,
    );
  }
}

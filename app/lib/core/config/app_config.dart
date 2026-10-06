import 'package:flutter/foundation.dart';

/// Build-time configuration, from `--dart-define`:
///
/// - `LUNAWAY_API`: base URL of the API. Release builds default to the
///   public API, debug and profile builds to the local backend.
/// - `LUNAWAY_DEMO=true`: synthetic places served on the device, no network.
/// - `LUNAWAY_STYLE_LIGHT`, `LUNAWAY_STYLE_DARK`: basemap style URLs, so the
///   self-hosted Protomaps style can replace OpenFreeMap without a code change.
@immutable
final class AppConfig {
  const new({
    required this.apiBaseUrl,
    required this.demo,
    required this.basemapLight,
    required this.basemapDark,
  });

  factory fromEnvironment() {
    const api = String.fromEnvironment('LUNAWAY_API');
    const light = String.fromEnvironment('LUNAWAY_STYLE_LIGHT');
    const dark = String.fromEnvironment('LUNAWAY_STYLE_DARK');
    return AppConfig(
      apiBaseUrl: api.isNotEmpty ? api : (kReleaseMode ? publicApi : localApi),
      demo: const bool.fromEnvironment('LUNAWAY_DEMO'),
      basemapLight: light.isNotEmpty ? light : openFreeMapLight,
      basemapDark: dark.isNotEmpty ? dark : openFreeMapDark,
    );
  }

  static const publicApi = 'https://api.lunaway.net';
  static const localApi = 'http://127.0.0.1:8484';

  /// OpenFreeMap: free, keyless, no tracking. Positron and Dark are quiet
  /// basemaps on which the coloured pins stand out.
  static const openFreeMapLight = 'https://tiles.openfreemap.org/styles/positron';
  static const openFreeMapDark = 'https://tiles.openfreemap.org/styles/dark';

  static const website = 'https://lunaway.net';
  static const privacyPolicy = 'https://lunaway.net/privacy';
  static const sourceCode = 'https://github.com/poka-IT/lunaway';

  final String apiBaseUrl;
  final bool demo;
  final String basemapLight;
  final String basemapDark;

  Uri get graphqlEndpoint => Uri.parse('${apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/graphql');

  /// The honest User-Agent of every request the app makes.
  static String userAgent(String version) => 'Lunaway/$version (+$website)';
}

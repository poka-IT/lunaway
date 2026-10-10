import 'package:flutter/foundation.dart';

/// Whether this build carries the demo mode: synthetic places served on the
/// device, no network. A compile-time constant, so a build without
/// `--dart-define=LUNAWAY_DEMO=true` (every release) leaves the demo data and
/// its fake server out of the binary: the compiler drops code under a false
/// constant.
const bool demoBuild = bool.fromEnvironment('LUNAWAY_DEMO');

/// Build-time configuration, from `--dart-define`:
///
/// - `LUNAWAY_API_URL`: base URL of the API, the public API by default. A
///   developer points it at a local or a staging server.
/// - `LUNAWAY_DEMO=true`: the demo mode (see [demoBuild]).
/// - `LUNAWAY_BASEMAP_URL`: base URL of the basemap host (TileJSON at
///   `planet.json`, glyphs under `fonts/`, sprites under `sprites/`), our
///   tile server by default. A developer points it at another deployment of
///   the same layout.
@immutable
final class AppConfig {
  const new({required this.apiBaseUrl, required this.demo, required this.basemapUrl});

  factory fromEnvironment() {
    const api = String.fromEnvironment('LUNAWAY_API_URL');
    const basemap = String.fromEnvironment('LUNAWAY_BASEMAP_URL');
    return AppConfig(
      apiBaseUrl: api.isNotEmpty ? api : publicApi,
      demo: demoBuild,
      basemapUrl: basemap.isNotEmpty ? basemap : publicBasemap,
    );
  }

  static const publicApi = 'https://api.lunaway.net';

  /// Our tile server: OpenStreetMap data in the Protomaps schema, with the
  /// glyphs and sprites the app's styles name.
  static const publicBasemap = 'https://tiles.lunaway.net';

  static const website = 'https://lunaway.net';
  static const sourceCode = 'https://github.com/poka-IT/lunaway';

  /// The languages the site serves under their own code; French, its
  /// default, is at the root (`tool/site/build.py`, `LANGS`).
  static const _siteLanguages = {'en', 'de', 'es', 'it', 'nl'};

  /// A page of the site ([path] without a leading slash: `privacy`,
  /// `account/delete`, or empty for the home page) in the app's [language],
  /// so the site opens in the language the user reads.
  static Uri sitePage(String language, String path) =>
      Uri.parse(_siteLanguages.contains(language) ? '$website/$language/$path' : '$website/$path');

  final String apiBaseUrl;
  final bool demo;
  final String basemapUrl;

  Uri get apiBase => Uri.parse(apiBaseUrl.replaceAll(RegExp(r'/+$'), ''));

  Uri get graphqlEndpoint => apiBase.replace(path: '${apiBase.path}/graphql');

  /// The basemap host's base URL, without a trailing slash.
  String get basemapBase => basemapUrl.replaceAll(RegExp(r'/+$'), '');

  /// Whether [url] is a photo served by the API's image proxy: the only
  /// images the app downloads. Same scheme, host and port as the API, under
  /// `/media/`.
  bool isApiMedia(Uri url) {
    final base = apiBase;
    return url.scheme == base.scheme &&
        url.host == base.host &&
        url.port == base.port &&
        url.path.startsWith('${base.path}/media/') &&
        !url.path.contains('..');
  }

  /// Whether [url] is the API's proxy of a photo of the external community
  /// source (`/external-photos/<uuid>/thumb` or `/large`): the API downloads
  /// the partner's file on the first request and answers with a redirect
  /// to its own copy under `/media/`.
  bool isApiExternalPhoto(Uri url) {
    final base = apiBase;
    return url.scheme == base.scheme &&
        url.host == base.host &&
        url.port == base.port &&
        !url.hasQuery &&
        url.path.startsWith('${base.path}/external-photos/') &&
        _externalPhotoPath.hasMatch(url.path.substring(base.path.length));
  }

  static final _externalPhotoPath = RegExp(
    r'^/external-photos/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/(thumb|large)$',
  );

  /// The honest User-Agent of every request the app makes.
  static String userAgent(String version) => 'Lunaway/$version (+$website)';
}

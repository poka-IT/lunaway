import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// The two basemap styles, Aube (light) and Minuit (dark), generated from
/// Protomaps basemaps by `tool/map_style/` and shipped as assets, so the map
/// has a style without network. They are templates: the tile host and the
/// label language are filled in by [fillBasemapStyle].
@immutable
final class BasemapTemplates {
  const new({required this.aube, required this.minuit});

  static const aubeAsset = 'assets/map/styles/aube.json';
  static const minuitAsset = 'assets/map/styles/minuit.json';

  /// A style with no layer, for tests that never draw a basemap.
  static const blank = BasemapTemplates(aube: _blank, minuit: _blank);
  static const _blank = '{"version":8,"sources":{},"layers":[]}';

  /// Both styles, read from the app's assets.
  static Future<BasemapTemplates> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    return BasemapTemplates(
      aube: await assets.loadString(aubeAsset, cache: false),
      minuit: await assets.loadString(minuitAsset, cache: false),
    );
  }

  final String aube;
  final String minuit;

  String of({required bool dark}) => dark ? minuit : aube;
}

/// The tokens the style generator leaves in the templates
/// (`tool/map_style/README.md`).
abstract final class BasemapTokens {
  static const tiles = '__LUNAWAY_TILES__';
  static const glyphs = '__LUNAWAY_GLYPHS__';
  static const sprite = '__LUNAWAY_SPRITE__';
  static const language = '__LUNAWAY_LANG__';
}

/// The label languages the app asks the styles for. Any language written in
/// the Latin script works the same way; these are the app's own locales.
const basemapLanguages = {'fr', 'en'};

/// The label language for an app locale code: the locale's own when the
/// styles carry it, English otherwise.
String basemapLanguage(String localeCode) {
  final language = localeCode.split(RegExp('[-_]')).first.toLowerCase();
  return basemapLanguages.contains(language) ? language : 'en';
}

/// [template] made into a style MapLibre can load: the vector source, the
/// glyphs and the sprite sheets come from the basemap host at [base] (the
/// layout of `infra/caddy`: `planet.json`, `fonts/`, `sprites/`), the labels
/// in [language].
///
/// The tokens sit inside JSON strings and are replaced as text, so a value
/// holding a quote or a backslash would break the document: such a [base] is
/// refused.
String fillBasemapStyle(String template, {required String base, required String language}) {
  final url = Uri.tryParse(base);
  if (url == null ||
      !(url.isScheme('https') || url.isScheme('http')) ||
      url.host.isEmpty ||
      base.contains('"') ||
      base.contains(r'\')) {
    throw ArgumentError.value(base, 'base', 'not an http(s) URL usable in a style');
  }
  final root = base.replaceAll(RegExp(r'/+$'), '');
  return template
      .replaceAll(BasemapTokens.tiles, '$root/planet.json')
      .replaceAll(BasemapTokens.glyphs, '$root/fonts')
      .replaceAll(BasemapTokens.sprite, '$root/sprites/protomaps-v4')
      .replaceAll(BasemapTokens.language, basemapLanguage(language));
}

/// [template] made into a style that reads no network: the vector tiles from
/// the downloaded PMTiles archive at [pack] (MapLibre Native's
/// `pmtiles://file://` source), the glyphs and sprites from [assets], where
/// the app copied the ones it carries (`assets/map/offline/`). The archive's
/// header says its last zoom; the map draws its tiles larger beyond it.
String fillOfflineBasemapStyle(
  String template, {
  required String pack,
  required String assets,
  required String language,
}) {
  String fileUrl(String path) {
    final url = Uri.file(path).toString();
    if (url.contains('"') || url.contains(r'\')) {
      throw ArgumentError.value(path, 'path', 'not usable in a style');
    }
    return url;
  }

  final root = assets.replaceAll(RegExp(r'/+$'), '');
  return template
      .replaceAll(BasemapTokens.tiles, 'pmtiles://${fileUrl(pack)}')
      .replaceAll(BasemapTokens.glyphs, fileUrl('$root/glyphs'))
      .replaceAll(BasemapTokens.sprite, fileUrl('$root/sprites'))
      .replaceAll(BasemapTokens.language, basemapLanguage(language));
}

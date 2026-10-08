import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/map_look.dart';

/// The shipped styles, read as the app reads them.
final _templates = BasemapTemplates(
  aube: File(BasemapTemplates.aubeAsset).readAsStringSync(),
  minuit: File(BasemapTemplates.minuitAsset).readAsStringSync(),
);

/// The image names and font stacks the tile host serves, recorded from the
/// basemaps-assets commit the server installs.
final _assets = jsonDecode(
  File('test/fixtures/basemap_assets.json').readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object?> _filled({required bool dark, String language = 'fr'}) => jsonDecode(
  fillBasemapStyle(
    _templates.of(dark: dark),
    base: AppConfig.publicBasemap,
    language: language,
  ),
) as Map<String, Object?>;

Iterable<Map<String, Object?>> _layers(Map<String, Object?> style) =>
    (style['layers']! as List).cast<Map<String, Object?>>();

/// Every string an expression can evaluate to, for the expression forms the
/// styles use to pick an image. The road shields name their sprite by the
/// length of the shield text; the sheets hold one to five characters, as
/// upstream's, and a longer text shows without a shield.
Set<String> _outcomes(Object? expression) {
  if (expression is String) return {expression};
  if (expression is! List || expression.isEmpty) {
    throw StateError('unexpected expression $expression');
  }
  final op = expression.first;
  final args = expression.sublist(1);
  switch (op) {
    case 'match':
      // input, then label and output pairs, then the fallback.
      return {
        for (var i = 2; i < args.length; i += 2) ..._outcomes(args[i]),
        ..._outcomes(args.last),
      };
    case 'case':
      return {
        for (var i = 1; i < args.length; i += 2) ..._outcomes(args[i]),
        ..._outcomes(args.last),
      };
    case 'step':
      return {
        ..._outcomes(args[1]),
        for (var i = 3; i < args.length; i += 2) ..._outcomes(args[i]),
      };
    case 'coalesce':
      return {for (final a in args) ..._outcomes(a)};
    case 'concat':
      var acc = {''};
      for (final part in args) {
        final values = part is List && part.first == 'length'
            ? {for (var n = 1; n <= 5; n++) '$n'}
            : _outcomes(part);
        acc = {
          for (final a in acc)
            for (final v in values) '$a$v',
        };
      }
      return acc;
  }
  throw StateError('expression $op is not handled: extend the test before shipping it');
}

/// The font names a `text-font` value can take: a plain stack, or a choice
/// between literal stacks.
Set<String> _fonts(Object? value) {
  if (value is List && value.isNotEmpty) {
    switch (value.first) {
      case 'literal':
        return (value[1] as List).cast<String>().toSet();
      case 'case':
        return {
          for (var i = 2; i < value.length; i += 2) ..._fonts(value[i]),
          ..._fonts(value.last),
        };
    }
    if (value.every((v) => v is String)) return value.cast<String>().toSet();
  }
  throw StateError('text-font $value is not handled: extend the test before shipping it');
}

void main() {
  for (final dark in [false, true]) {
    final name = dark ? 'Minuit' : 'Aube';
    final sheet = dark ? 'dark' : 'light';

    group(name, () {
      test('points every resource at the tile host and leaves no token behind', () {
        final text = fillBasemapStyle(
          _templates.of(dark: dark),
          base: '${AppConfig.publicBasemap}/',
          language: 'fr',
        );
        expect(text, isNot(contains('__LUNAWAY_')));
        final style = jsonDecode(text) as Map<String, Object?>;
        expect(style['version'], 8);
        expect(style['glyphs'], 'https://tiles.lunaway.net/fonts/{fontstack}/{range}.pbf');
        expect(style['sprite'], 'https://tiles.lunaway.net/sprites/protomaps-v4/$sheet');
        final sources = style['sources']! as Map<String, Object?>;
        expect(sources.values.map((s) => (s! as Map)['url']), [
          'https://tiles.lunaway.net/planet.json',
        ]);
        // No third-party host: every URL of the style is ours.
        final hosts = RegExp('https?://([^/"]+)').allMatches(text).map((m) => m[1]).toSet()
          ..removeAll(['github.com', 'www.openstreetmap.org']);
        expect(hosts, {'tiles.lunaway.net'}, reason: 'only attribution links point elsewhere');
      });

      test('credits OpenStreetMap and Protomaps in its source attribution', () {
        final sources = _filled(dark: dark)['sources']! as Map<String, Object?>;
        final attribution = (sources.values.single! as Map)['attribution'] as String;
        expect(attribution, contains('OpenStreetMap'));
        expect(attribution, contains('Protomaps'));
      });

      test('labels places in the language asked for', () {
        final fr = jsonEncode(_filled(dark: dark)['layers']);
        final en = jsonEncode(_filled(dark: dark, language: 'en')['layers']);
        expect(fr, contains('name:fr'));
        expect(en, contains('name:en'));
        expect(en, isNot(contains('name:fr')));
      });

      test('names only images its sprite sheet holds', () {
        final images = (_assets['sprites']! as Map)[sheet] as List;
        final named = {
          for (final layer in _layers(_filled(dark: dark)))
            if ((layer['layout'] as Map?)?['icon-image'] case final Object image)
              ..._outcomes(image),
        }..remove('');
        expect(named, isNotEmpty);
        expect(named.difference(images.toSet()), isEmpty);
      });

      test('uses only the font stacks the tile host serves', () {
        final fonts = (_assets['fonts']! as List).toSet();
        final used = {
          for (final layer in _layers(_filled(dark: dark)))
            if ((layer['layout'] as Map?)?['text-font'] case final Object stack) ..._fonts(stack),
          ...MapLook.clusterFont,
        };
        expect(used.difference(fonts), isEmpty);
      });
    });
  }

  test('a base that would break the style document is refused', () {
    for (final base in [
      'https://tiles.example.org/a"b',
      r'https://x.org/\',
      'file:///tmp',
      'tiles',
    ]) {
      expect(
        () => fillBasemapStyle('{}', base: base, language: 'fr'),
        throwsArgumentError,
        reason: base,
      );
    }
  });

  test('the map labels in each language of the app, and in English for any other', () {
    expect(basemapLanguage('fr'), 'fr');
    expect(basemapLanguage('fr_FR'), 'fr');
    expect(basemapLanguage('en-GB'), 'en');
    expect(basemapLanguage('de'), 'de');
    expect(basemapLanguage('es_ES'), 'es');
    expect(basemapLanguage('it'), 'it');
    expect(basemapLanguage('nl-BE'), 'nl');
    expect(basemapLanguage('pt'), 'en');
    for (final locale in AppLocale.values) {
      expect(
        basemapLanguage(locale.languageCode),
        locale.languageCode,
        reason: 'the map names places in the language of the screens',
      );
    }
  });

  test('the release build reads the basemap from our tile host', () {
    final config = AppConfig.fromEnvironment();
    expect(config.basemapBase, 'https://tiles.lunaway.net');
  });
}

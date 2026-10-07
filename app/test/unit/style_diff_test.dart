import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/features/map/domain/basemap_style.dart';
import 'package:lunaway/features/map/domain/style_diff.dart';

final _templates = BasemapTemplates(
  aube: File(BasemapTemplates.aubeAsset).readAsStringSync(),
  minuit: File(BasemapTemplates.minuitAsset).readAsStringSync(),
);

String _style({required bool dark, String language = 'fr'}) => fillBasemapStyle(
  _templates.of(dark: dark),
  base: AppConfig.publicBasemap,
  language: language,
);

void main() {
  test('day to night is paint and sprite only: the theme turns without a reload', () {
    final diff = StyleDiff.between(_style(dark: false), _style(dark: true));
    expect(diff, isNotNull, reason: 'Aube and Minuit share sources, layers and layout');
    expect(diff!.changesSprite, isTrue);
    expect(diff.spriteTo, endsWith('/dark'));
    final layers = (jsonDecode(_style(dark: true)) as Map)['layers'] as List;
    // Every layer whose colours differ is in the diff, with Minuit's values.
    for (final layer in layers.cast<Map<String, Object?>>()) {
      final changed = diff.paint[layer['id']];
      if (changed == null) continue;
      final paint = layer['paint']! as Map;
      for (final MapEntry(:key, :value) in changed.entries) {
        expect(value, paint[key], reason: '${layer['id']} $key');
      }
    }
    expect(diff.paint, isNotEmpty);
  });

  test('night to day turns back to Aube', () {
    final diff = StyleDiff.between(_style(dark: true), _style(dark: false))!;
    expect(diff.spriteTo, endsWith('/light'));
    final there = StyleDiff.between(_style(dark: false), _style(dark: true))!;
    expect(diff.paint.keys.toSet(), there.paint.keys.toSet());
  });

  test('another language changes the labels: the style loads whole', () {
    expect(StyleDiff.between(_style(dark: false), _style(dark: false, language: 'en')), isNull);
  });

  test('the same style changes nothing', () {
    expect(StyleDiff.between(_style(dark: true), _style(dark: true))!.isEmpty, isTrue);
  });

  test('a style URL or another source is loaded whole', () {
    expect(StyleDiff.between('https://example.org/style.json', _style(dark: true)), isNull);
    final other = (jsonDecode(_style(dark: true)) as Map<String, Object?>)
      ..['sources'] = {
        'protomaps': {'type': 'vector', 'url': 'pmtiles://file:///pack.pmtiles'},
      };
    expect(StyleDiff.between(_style(dark: false), jsonEncode(other)), isNull);
  });
}

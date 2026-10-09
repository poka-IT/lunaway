import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/shared/theme/luna_scheme.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// WCAG 2.2 relative luminance of an opaque colour.
double luminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// The contrast ratio of [fg] drawn over [bg], a translucent [fg] composited
/// first, as the screen shows it.
double contrast(Color fg, Color bg) {
  final top = Color.alphaBlend(fg, bg);
  final a = luminance(top);
  final b = luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// Text needs 4.5:1 (WCAG AA, normal size); icons and the edges a user must
/// see to use a control need 3:1 (non-text contrast).
const text = 4.5;
const graphic = 3.0;

void main() {
  for (final (name, scheme, tokens) in [
    ('Aube', LunaScheme.aube, LunaTokens.aube),
    ('Minuit', LunaScheme.minuit, LunaTokens.minuitTheme),
  ]) {
    group(name, () {
      final surfaces = {
        'surface': scheme.surface,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'floatingSurface': tokens.floatingSurface,
      };

      final pairs = <String, (Color, Color, double)>{
        for (final s in surfaces.entries) ...{
          'onSurface on ${s.key}': (scheme.onSurface, s.value, text),
          'onSurfaceVariant on ${s.key}': (scheme.onSurfaceVariant, s.value, text),
          'link on ${s.key}': (tokens.link, s.value, text),
          'error on ${s.key}': (scheme.error, s.value, text),
        },
        'onPrimary on primary': (scheme.onPrimary, scheme.primary, text),
        'onPrimaryContainer on primaryContainer': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
          text,
        ),
        'onSurface on primaryContainer (selected rows and chips)': (
          scheme.onSurface,
          scheme.primaryContainer,
          text,
        ),
        'onSecondary on secondary': (scheme.onSecondary, scheme.secondary, text),
        'onSecondaryContainer on secondaryContainer': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          text,
        ),
        'onTertiary on tertiary': (scheme.onTertiary, scheme.tertiary, text),
        'onTertiaryContainer on tertiaryContainer': (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
          text,
        ),
        'onError on error': (scheme.onError, scheme.error, text),
        'onErrorContainer on errorContainer': (
          scheme.onErrorContainer,
          scheme.errorContainer,
          text,
        ),
        'onInverseSurface on inverseSurface (messages)': (
          scheme.onInverseSurface,
          scheme.inverseSurface,
          text,
        ),
        'inversePrimary on inverseSurface (message actions)': (
          scheme.inversePrimary,
          scheme.inverseSurface,
          text,
        ),
        'dock labels': (tokens.dockForeground, tokens.dockSurface, text),
        'selected dock label': (tokens.dockOnSelected, tokens.dockSelected, text),
        'photo viewer text': (tokens.onPhotoBackdrop, tokens.photoBackdrop, text),
        'photo viewer muted text': (tokens.onPhotoBackdropMuted, tokens.photoBackdrop, text),
        for (final f in KindFamily.values) ...{
          'family text ${f.name} on surface': (tokens.familyText[f]!, scheme.surface, text),
          'pin glyph on ${f.name}': (LunaTokens.pinGlyph, LunaTokens.familyFill(f), graphic),
        },
        // The glyph of a point's pin, avatar and chip on its category's
        // tone: what tells a restaurant from a museum.
        for (final c in PoiCategory.values)
          'point glyph on the ${c.name} tone': (LunaTokens.pinGlyph, PoiLook.tone(c), text),
        for (final o in OvernightStatus.values) ...{
          'night label ${o.name} on surface': (tokens.night[o]!.label, scheme.surface, text),
          'night label ${o.name} on floating surface': (
            tokens.night[o]!.label,
            tokens.floatingSurface,
            text,
          ),
          if (tokens.night[o]!.disc.a > 0)
            'night glyph ${o.name} on its disc': (
              tokens.night[o]!.glyph,
              tokens.night[o]!.disc,
              graphic,
            ),
          // The badge reads by its disc (or ring) or by its glyph: one of
          // them must stand out from the surface.
          'night badge ${o.name} on surface': (
            [
              tokens.night[o]!.glyph,
              ?tokens.night[o]!.ring,
              if (tokens.night[o]!.disc.a > 0) tokens.night[o]!.disc,
            ].reduce((a, b) => contrast(a, scheme.surface) >= contrast(b, scheme.surface) ? a : b),
            scheme.surface,
            graphic,
          ),
        },
        'outline on surface (field borders)': (scheme.outline, scheme.surface, graphic),
      };

      for (final p in pairs.entries) {
        test(p.key, () {
          final (fg, bg, min) = p.value;
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(min),
            reason: '${p.key}: ${contrast(fg, bg).toStringAsFixed(2)}:1, needs $min:1',
          );
        });
      }
    });
  }

  test('the contrast formula matches the WCAG reference values', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrast(const Color(0xFF777777), Colors.white), closeTo(4.48, 0.01));
  });
}

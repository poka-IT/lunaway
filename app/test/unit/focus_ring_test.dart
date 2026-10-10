import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/tokens.dart';

import 'contrast_test.dart' show contrast, graphic;

/// The ring the theme draws round what holds the keyboard's focus stands
/// out from the pixels it replaces, the control's own fill, in both
/// themes: 3:1 at least, the contrast of a control's edge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  const focused = {WidgetState.focused};
  const focusedOn = {WidgetState.focused, WidgetState.selected};

  for (final brightness in Brightness.values) {
    final theme = lunaTheme(brightness);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<LunaTokens>()!;
    // The control, its states when focused, and the fill under its edge.
    final controls = <(String, BorderSide? Function(Set<WidgetState>), Set<WidgetState>, Color)>[
      ('filled', (s) => theme.filledButtonTheme.style!.side!.resolve(s), focused, scheme.primary),
      (
        'outlined',
        (s) => theme.outlinedButtonTheme.style!.side!.resolve(s),
        focused,
        scheme.surface,
      ),
      ('text', (s) => theme.textButtonTheme.style!.side!.resolve(s), focused, scheme.surface),
      (
        'elevated',
        (s) => theme.elevatedButtonTheme.style!.side!.resolve(s),
        focused,
        scheme.surfaceContainerHigh,
      ),
      ('icon', (s) => theme.iconButtonTheme.style!.side!.resolve(s), focused, scheme.surface),
      (
        'chip',
        (s) => (theme.chipTheme.side! as WidgetStateBorderSide).resolve(s),
        focused,
        scheme.surfaceContainerLow,
      ),
      (
        'chip selected',
        (s) => (theme.chipTheme.side! as WidgetStateBorderSide).resolve(s),
        focusedOn,
        scheme.primaryContainer,
      ),
      (
        'segment selected',
        (s) => theme.segmentedButtonTheme.style!.side!.resolve(s),
        focusedOn,
        scheme.primary,
      ),
      (
        'segment',
        (s) => theme.segmentedButtonTheme.style!.side!.resolve(s),
        focused,
        scheme.surface,
      ),
      // The guidance's bar (`_panelColors`): its cross sets its own ink.
      (
        'guidance bar button',
        (s) =>
            focusRingIn(brightness == Brightness.light ? tokens.dockForeground : scheme.onSurface)
                .resolve(s),
        focused,
        brightness == Brightness.light ? tokens.dockSurface : tokens.floatingSurface,
      ),
    ];

    for (final (name, side, states, fill) in controls) {
      test('${brightness.name}: the $name ring stands out from its fill', () {
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        final ring = side(states)!;
        expect(ring.width, greaterThanOrEqualTo(2));
        expect(contrast(ring.color, fill), greaterThanOrEqualTo(graphic), reason: name);
      });
    }

    test('${brightness.name}: a touch shows no ring', () {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      expect(theme.filledButtonTheme.style!.side!.resolve(focused), isNull);
      expect(theme.iconButtonTheme.style!.side!.resolve(focused), isNull);
      expect(focusRingIn(scheme.onSurface).resolve(focused), isNull);
    });
  }
}

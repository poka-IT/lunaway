import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Where the OpenStreetMap copyright page lives: the credit opens it.
final Uri osmCopyright = Uri.parse('https://www.openstreetmap.org/copyright');

/// The basemap's credit, always visible in the bottom left corner of the
/// map: the OpenStreetMap licence asks for it on the map itself, and
/// Protomaps for its style. The engines' own attribution controls only show
/// it behind a tap, or not at all in the desktop web view: the map hides
/// theirs (GlMap's attribution margins), this one stands alone.
class MapCredit extends ConsumerWidget {
  const new({super.key});

  /// Its height on the map: a finger-sized target around a small label.
  static const double height = 48;

  /// Its width on the map at the reader's text size: what a control on the
  /// same bottom edge leaves free for it.
  static double widthOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: context.t.map.credit, style: _style(Theme.of(context))),
      textDirection: Directionality.of(context),
      textScaler: _scaler(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + Space.xs * 2;
  }

  static TextStyle? _style(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface);

  // A legal line, not reading matter: at large text sizes it would run under
  // the map's buttons.
  static TextScaler _scaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void open() => ref.read(externalActionsProvider).openUrl(osmCopyright);
    // A link the keyboard reaches too, Enter or Space opening it, with the
    // theme's ring round the label while it holds the focus.
    return _Focusable(
      label: t.map.creditLabel,
      onActivate: open,
      builder: ({required focused}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        // A small label, a finger-sized target: 48 dp tall at least.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.surface.withValues(alpha: 0.78),
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(LunaTokens.radiusXs)),
                  side: focused ? focusRing(scheme.onSurface) : BorderSide.none,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
                child: Text(t.map.credit, style: _style(theme), textScaler: _scaler(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A control the app draws itself: in the keyboard's round, activated by
/// Enter or Space, the pointing hand under a mouse, one button for the
/// screen readers named [label]; [builder] learns when to show the focus.
class _Focusable extends StatefulWidget {
  const new({required this.label, required this.onActivate, required this.builder});

  final String label;
  final VoidCallback onActivate;
  final Widget Function({required bool focused}) builder;

  @override
  State<_Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<_Focusable> {
  final _node = FocusNode(debugLabel: 'map credit');

  /// The ring: the focus, shown in the keyboard's highlight mode only.
  bool _ringed = false;
  bool _hasFocus = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    onTap: widget.onActivate,
    // Stated here, the label's own node left out: a browser moves its
    // focus to a node that says it can take it.
    focusable: true,
    focused: _hasFocus,
    // A screen reader that moves onto it moves the keyboard's focus there.
    onFocus: _node.requestFocus,
    excludeSemantics: true,
    child: FocusableActionDetector(
      focusNode: _node,
      mouseCursor: SystemMouseCursors.click,
      // Enter sends ButtonActivateIntent in a browser, ActivateIntent
      // elsewhere; Space sends ActivateIntent everywhere.
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onActivate()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onActivate(),
        ),
      },
      onShowFocusHighlight: (shown) => setState(() => _ringed = shown),
      onFocusChange: (focused) => setState(() => _hasFocus = focused),
      child: widget.builder(focused: _ringed),
    ),
  );
}

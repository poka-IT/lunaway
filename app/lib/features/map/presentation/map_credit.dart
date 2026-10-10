import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/features/map/application/map_credit_fold.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/app_theme.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

/// Where the OpenStreetMap copyright page lives: the credits open it.
final Uri osmCopyright = Uri.parse('https://www.openstreetmap.org/copyright');

/// Where the Protomaps basemaps and their licence live.
final Uri protomapsBasemaps = Uri.parse('https://github.com/protomaps/basemaps');

/// How long a map shows its credit in full before it folds, unless the
/// user presses on the map first: the "five seconds" of the guidelines.
const Duration mapCreditInFull = Duration(seconds: 5);

/// The basemap's credit, in a bottom corner of every map (the main map, the
/// placement of a place, the route's preview, the guidance). The engines'
/// own attribution controls are hidden: the attribution margins of
/// GlLunaMap and GlRouteMap, the page's CSS; the desktop page adds none.
///
/// What it shows follows the OpenStreetMap Foundation's attribution
/// guidelines (osmfoundation.org/wiki/Licence/Attribution_Guidelines,
/// adopted 2021-06-25, read 2026-10-10). "© OpenStreetMap", a form they
/// accept, shows without a tap; it folds into an "(i)" at the first press
/// on the map or after [mapCreditInFull] on screen, as they allow for an
/// interactive map, and stays folded on the maps opened after it in the
/// run ([MapCreditFolded]). A tap on it, folded or not, opens the credits
/// ([showMapCredits]): OpenStreetMap with the ODbL and its copyright page,
/// the Protomaps style (a credit its authors ask for without requiring
/// it), and where the profile lists every source. The smallest form the
/// guidelines allow, so the map keeps its room (the PO's rule of
/// 2026-10-10).
///
/// With [photos], a line names the source of the photos the route maps
/// draw (`RichStyle.credited`) and folds with the rest: the external
/// community source's agreement lets its mention stand on a screen about
/// the sources or anywhere reasonably reached (art. 5.3, read by the PO on
/// 2026-10-10), so it shows in full with the credit, then in the credits'
/// sheet and in the profile's sources. A place's page keeps it beside its
/// photos.
class MapCredit extends ConsumerStatefulWidget {
  const new({this.photos = false, this.caption = false, super.key});

  /// The map may draw the places' photos (the route maps).
  final bool photos;

  /// A caption that a touch passes through to the map, with no target of
  /// its own: over the guidance, a stray touch while driving opens nothing.
  /// The licence stays a few taps away in the profile's credits, as the
  /// guidelines allow once the credit has folded ("an ‘About’ option in a
  /// menu").
  final bool caption;

  /// Its height on the map: a finger-sized target around a small mark.
  static const double height = 48;

  /// The room around the mark's icon, inside its ground.
  static const double _inset = Space.xxs;

  /// Its width on the map at the reader's text size, unfolded: what a
  /// control on the same bottom edge leaves free for it. Folded it takes
  /// less, never more.
  static double widthOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: context.t.map.credit, style: _style(Theme.of(context))),
      textDirection: Directionality.of(context),
      textScaler: _scaler(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _iconSize(context) + width + _inset * 2.5 + Space.xxs;
  }

  /// The height its ground takes at [width], unfolded, with the photos'
  /// line or without: the guidance keeps the vehicle clear of it.
  static double heightOf(BuildContext context, double width, {required bool photos}) {
    final t = context.t;
    final icon = _iconSize(context);
    final room = math.max<double>(1, width - icon - _inset * 2.5 - Space.xxs);
    var lines = 0.0;
    for (final text in [t.map.credit, if (photos) t.map.creditPhotos]) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _style(Theme.of(context))),
        textDirection: Directionality.of(context),
        textScaler: _scaler(context),
      )..layout(maxWidth: room);
      lines += painter.height;
      painter.dispose();
    }
    return math.max(icon + _inset * 2, lines + _inset);
  }

  static TextStyle? _style(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface);

  // A legal line, not reading matter: at large text sizes it would run under
  // the map's buttons.
  static TextScaler _scaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

  static double _iconSize(BuildContext context) => _scaler(context).scale(14);

  @override
  ConsumerState<MapCredit> createState() => _MapCreditState();
}

class _MapCreditState extends ConsumerState<MapCredit> {
  Timer? _fold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The five seconds run while the credit is on screen: a map under a
    // page or on a tab not shown has shown nothing yet.
    if (!TickerMode.valuesOf(context).enabled || ref.read(mapCreditFoldedProvider)) {
      _fold?.cancel();
      _fold = null;
      return;
    }
    _fold ??= Timer(mapCreditInFull, () {
      if (mounted) ref.read(mapCreditFoldedProvider.notifier).fold();
    });
  }

  @override
  void dispose() {
    _fold?.cancel();
    super.dispose();
  }

  void _open() => unawaited(showMapCredits(context, photos: widget.photos));

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folded = ref.watch(mapCreditFoldedProvider);
    final photos = widget.photos;
    final style = MapCredit._style(theme);
    final scaler = MapCredit._scaler(context);
    final icon = MapCredit._iconSize(context);
    const inset = MapCredit._inset;
    final texts = folded ? const <String>[] : [t.map.credit, if (photos) t.map.creditPhotos];
    final mark = icon + inset * 2;
    Widget ground({required bool ringed}) => AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          // The map's ground under its controls: readable over any basemap,
          // in both themes.
          color: scheme.surface.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(mark / 2)),
            side: ringed ? focusRing(scheme.onSurface) : BorderSide.none,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: mark, minHeight: mark),
          child: Padding(
            padding: texts.isEmpty
                ? EdgeInsets.zero
                : const EdgeInsetsDirectional.fromSTEB(inset, inset / 2, inset * 1.5, inset / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Folded, the mark stands for the words a screen reader
                // still reads over the guidance.
                Semantics(
                  label: folded && widget.caption
                      ? [t.map.credit, if (photos) t.map.creditPhotos].join('. ')
                      : null,
                  excludeSemantics: true,
                  child: Icon(AppIcons.mapCredit, size: icon, color: scheme.onSurface),
                ),
                if (texts.isNotEmpty) ...[
                  const SizedBox(width: Space.xxs),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final text in texts)
                          Text(
                            text,
                            style: style,
                            textScaler: scaler,
                            // Wrapped, the ground hugs the longest line
                            // rather than the room it may take.
                            textWidthBasis: TextWidthBasis.longestLine,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.caption) {
      return IgnorePointer(child: ExcludeFocus(child: ground(ringed: false)));
    }
    // A small mark, a finger-sized target: 48 dp each way at least, level
    // with the engines' own controls.
    Widget target({required bool ringed}) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MapCredit.height, minWidth: MapCredit.height),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        heightFactor: 1,
        child: Tooltip(
          message: t.map.creditsTitle,
          excludeFromSemantics: true,
          child: ground(ringed: ringed),
        ),
      ),
    );
    // A link the keyboard reaches too, Enter or Space opening it, with the
    // theme's ring round the mark while it holds the focus.
    return _Focusable(
      label: photos ? t.map.creditPhotosLabel : t.map.creditLabel,
      onActivate: _open,
      builder: ({required focused}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: target(ringed: focused),
      ),
    );
  }
}

/// The map's credits in a sheet over the map: OpenStreetMap and its
/// licence, the basemap's style, the photos' source while a map draws
/// them, and where every source is listed.
Future<void> showMapCredits(BuildContext context, {bool photos = false}) => showSheet<void>(
  context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => MapCredits(photos: photos),
);

/// The body of [showMapCredits], public for the tests.
class MapCredits extends ConsumerWidget {
  const new({this.photos = false, super.key});

  final bool photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    void open(Uri url) => unawaited(ref.read(externalActionsProvider).openUrl(url));
    const external = Icon(AppIcons.openExternal, size: 20);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
              child: Semantics(
                header: true,
                child: Text(t.map.creditsTitle, style: theme.textTheme.titleLarge),
              ),
            ),
            ListTile(
              title: Text(t.map.creditsOsm),
              subtitle: Text(t.map.creditsOsmLicence),
              trailing: external,
              onTap: () => open(osmCopyright),
            ),
            ListTile(
              title: Text(t.map.creditsStyle),
              trailing: external,
              onTap: () => open(protomapsBasemaps),
            ),
            if (photos) ListTile(title: Text(t.map.creditPhotos)),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: Text(
                t.map.creditsAll,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
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

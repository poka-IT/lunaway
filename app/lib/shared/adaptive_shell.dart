import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/presentation/account_section.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/brand_mark.dart';
import 'package:lunaway/shared/widgets/centred_clear.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/tab_reselect.dart';

/// The height the phone's floating dock takes above the bottom inset,
/// margins included. Screens read it through `MediaQuery.paddingOf`, which
/// the shell grows by this much, so nothing hides under the dock.
const double dockSpace = 64 + Space.m * 2;

/// The page's own colour rising from the bottom edge behind a floating bar
/// (the dock, a place's actions): the content scrolling under the bar
/// fades out instead of showing between it and the edge.
class BottomFade extends StatelessWidget {
  const new({super.key});

  /// How far above the bar the fade begins.
  static const double lead = Space.xxl;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surface.withValues(alpha: 0), surface.withValues(alpha: 0.92), surface],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

/// The frame around the top-level destinations: a floating dock on a phone,
/// a rail on a tablet, an extended rail on a desktop or a wide browser
/// window. On the map, a selected place takes the dock's place with its
/// own actions.
class AdaptiveShell extends ConsumerWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  // Tapping the current destination again returns to its first page, and
  // brings its list back to the top.
  void _go(WidgetRef ref, int index) {
    final again = index == shell.currentIndex;
    shell.goBranch(index, initialLocation: again);
    if (again) ref.read(tabReselectProvider.notifier).reselect(index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    // The first contribution made the account: say so once, with its name
    // and the recovery card, wherever the user is.
    ref.listen(accountControllerProvider, (previous, next) {
      // The key stopped opening the account (removed from another device,
      // deleted elsewhere): the profile now offers the recovery card.
      if (next is NoAccount && next.lost && previous is SignedIn) {
        showMessage(
          ScaffoldMessenger.maybeOf(context),
          t.account.lost,
          action: SnackBarAction(
            label: t.account.lostAction,
            onPressed: () => GoRouter.of(context).go(AppRoutes.recover),
          ),
        );
        return;
      }
      final fresh = next is SignedIn && next.justCreated;
      final before = previous is SignedIn && previous.justCreated;
      if (!fresh || before) return;
      ref.read(accountControllerProvider.notifier).welcomed();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) unawaited(showAccountWelcome(context, next.account));
      });
    });
    final destinations = [
      _Destination(AppIcons.map, AppIcons.mapSelected, t.nav.map),
      _Destination(AppIcons.favorite, AppIcons.favoriteSelected, t.nav.favorites),
      _Destination(AppIcons.profile, AppIcons.profileSelected, t.nav.profile),
    ];
    final size = WindowSize.of(context);
    // The system back on Favourites or Profile returns to the map, the
    // first destination, rather than leaving the app from there.
    Widget backToMap(Widget child) => PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: child,
    );

    if (size == .compact) {
      final placeOpen = shell.currentIndex == 0 && ref.watch(selectionProvider) != null;
      final media = MediaQuery.of(context);
      return backToMap(
        _Messages(
          // The dock's slot: its height and the margin under it. A message
          // floats above that slot, and above the taller bar of a place's
          // actions that takes the dock's place.
          reserved: 64 + math.max(media.padding.bottom, Space.m),
          // A message stands on the bar's slot, its fade included.
          slot: BottomFade.lead + 64 + math.max(media.padding.bottom, Space.m),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            // The dock is the Scaffold's bottom bar, drawn over the content.
            extendBody: true,
            body: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: media.padding.bottom + dockSpace),
              ),
              child: shell,
            ),
            bottomNavigationBar: AnimatedSlide(
              duration: Motion.of(context, Motion.medium),
              curve: placeOpen ? Motion.exit : Motion.enter,
              offset: placeOpen ? const Offset(0, 1.4) : Offset.zero,
              child: AnimatedOpacity(
                duration: Motion.of(context, Motion.short),
                opacity: placeOpen ? 0 : 1,
                child: IgnorePointer(
                  ignoring: placeOpen,
                  child: Stack(
                    children: [
                      // What scrolls under the dock fades into the page rather
                      // than running under it and under the system's gesture
                      // bar; taps go through the fade.
                      const Positioned.fill(child: IgnorePointer(child: BottomFade())),
                      Padding(
                        padding: const EdgeInsets.only(top: BottomFade.lead),
                        child: SafeArea(
                          top: false,
                          left: false,
                          right: false,
                          minimum: const EdgeInsets.only(bottom: Space.m),
                          // In the middle of the screen; a camera cut-out on
                          // one side moves it only by what it would cover.
                          child: CentredClear(
                            heightFactor: 1,
                            obstacles: [
                              SideRoom.left(media.padding.left),
                              SideRoom.right(media.padding.right),
                            ],
                            child: _Dock(
                              key: const ValueKey('dock'),
                              destinations: destinations,
                              selected: shell.currentIndex,
                              onSelected: (i) => _go(ref, i),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // On wide screens a message floats centred on the page beside the rail,
    // or on the map beside the panes, above the panes' action bars at their
    // foot.
    final folded = ref.watch(settingsProvider.select((s) => s.railCollapsed));
    return backToMap(
      _Messages(
        reserved: 0,
        // As the Scaffold floats a message: above the keyboard while it
        // shows, else above the bottom inset.
        slot: switch (MediaQuery.viewInsetsOf(context).bottom) {
          0 => MediaQuery.viewPaddingOf(context).bottom,
          final keyboard => keyboard,
        },
        maxWidth: 440,
        child: Scaffold(
          body: Row(
            children: [
              _Rail(
                destinations: destinations,
                selected: shell.currentIndex,
                onSelected: (i) => _go(ref, i),
                extended: size == .expanded && !folded,
                onFold: size == .expanded
                    ? () => ref.read(settingsProvider.notifier).setRailCollapsed(collapsed: !folded)
                    : null,
              ),
              Expanded(
                // The rail grows by the left camera cut-out: the page beside
                // it has no left edge of the screen to keep clear, and its
                // SafeArea would count the cut-out a second time.
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  child: MessageStage(child: shell),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floats the messages of [child] (a Scaffold) clear of the bars of actions
/// below them, centred on the stage of the screen shown ([MessageStage]),
/// else on the window, and aside from a button of the map level with them
/// ([PushesMessagesAside]): [reserved] is what the Scaffold already keeps at
/// its foot for the bars, [slot] how far above the bottom of the window it
/// sets a message's margin, [maxWidth] the widest a message gets (the whole
/// stage without one).
class _Messages extends StatefulWidget {
  const new({required this.reserved, required this.slot, required this.child, this.maxWidth});

  final double reserved;
  final double slot;
  final double? maxWidth;
  final Widget child;

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  final _clearance = MessageClearance();

  @override
  void dispose() {
    _clearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MessageClearanceScope(
    clearance: _clearance,
    child: ListenableBuilder(
      listenable: _clearance,
      // Only the messages' own theme changes: a whole Theme would rebuild
      // the app each time a place opens.
      builder: (context, child) {
        final bottom = math.max(Space.l, _clearance.value + Space.s - widget.reserved);
        final window = MediaQuery.sizeOf(context);
        final stage = _clearance.stage ?? (left: 0.0, right: window.width);
        // A message of one line at the reader's text size: an estimate, its
        // real height is known only once it shows.
        final foot = window.height - widget.slot - bottom;
        final head = foot - MediaQuery.textScalerOf(context).scale(kMinInteractiveDimension);
        return SnackBarTheme(
          data: SnackBarTheme.of(context).copyWith(
            insetPadding: messageInsets(
              context,
              left: stage.left,
              right: stage.right,
              maxWidth: widget.maxWidth,
              clear: _clearance.clearOf(stage, top: head, bottom: foot),
              bottom: bottom,
            ),
          ),
          child: child!,
        );
      },
      child: widget.child,
    ),
  );
}

final class _Destination {
  new(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The phone's navigation: a pill floating above the content, navy by day
/// and cream by night, the current destination lit in amber.
class _Dock extends StatelessWidget {
  const new({
    required this.destinations,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = LunaTokens.of(context);
    // The dock's labels sit under their icons in a 64 dp pill: the small
    // label style.
    final text = Theme.of(context).textTheme.labelSmall;
    final width = MediaQuery.sizeOf(context).width;
    return OverMap(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Container(
          constraints: BoxConstraints(maxWidth: width < 400 ? width - Space.xxl * 2 : 340),
          height: 64,
          padding: const EdgeInsets.all(Space.xs),
          decoration: BoxDecoration(
            color: tokens.dockSurface,
            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
            boxShadow: tokens.floatingShadow,
          ),
          child: Row(
            children: [
              for (final (i, d) in destinations.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == selected,
                    button: true,
                    label: d.label,
                    // The label replaces the icon and text below, and with
                    // them the ink's own tap: the node carries it again, or
                    // a screen reader could not switch tabs.
                    onTap: () => onSelected(i),
                    excludeSemantics: true,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                        onTap: () {
                          Haptics.select();
                          onSelected(i);
                        },
                        child: AnimatedContainer(
                          duration: Motion.of(context, Motion.medium),
                          curve: Motion.standard,
                          decoration: BoxDecoration(
                            color: i == selected ? tokens.dockSelected : Colors.transparent,
                            borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                i == selected ? d.selectedIcon : d.icon,
                                size: 22,
                                color: i == selected
                                    ? tokens.dockOnSelected
                                    : tokens.dockForeground,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                d.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: MediaQuery.textScalerOf(context)
                                    .clamp(maxScaleFactor: 1.3),
                                style: text?.copyWith(
                                  color: i == selected
                                      ? tokens.dockOnSelected
                                      : tokens.dockForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The width of the rail, before the safe area on its side: [dense] for the
/// desktop look (a mouse), narrower with shorter pills. The web page's first
/// map leaves the same room (`premapDefaults`).
double railWidth({required bool extended, required bool dense}) =>
    extended ? (dense ? 200.0 : 232.0) : (dense ? 76.0 : 92.0);

/// The navigation of the wide layouts: the brand at the top, the
/// destinations as amber-lit pills, labels under the icons (medium, or a
/// desktop rail folded by the user) or beside them (expanded). On a desktop
/// a button at its foot folds it to its icons and back ([onFold]).
class _Rail extends StatelessWidget {
  const new({
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.extended,
    this.onFold,
  });

  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool extended;

  /// Folds an extended rail, unfolds a folded one; null where the window
  /// leaves no choice (medium).
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    // The desktop look (a mouse): a narrower rail with shorter pills.
    final dense = theme.visualDensity.vertical < 0;
    final width = railWidth(extended: extended, dense: dense);
    return Container(
      // A phone on its side puts its camera cut-out on the left: the rail
      // grows by it, so its labels keep their room.
      width: width + MediaQuery.paddingOf(context).left,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                extended ? Space.xl : 0,
                dense ? Space.l : Space.xl,
                0,
                dense ? Space.xl : Space.xxl,
              ),
              child: extended
                  ? BrandLockup(height: dense ? 28 : 34)
                  : BrandMark(height: dense ? 32 : 38),
            ),
            for (final (i, d) in destinations.indexed)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? Space.m : Space.s,
                  vertical: dense ? Space.hair : Space.xxs,
                ),
                child: Semantics(
                  selected: i == selected,
                  button: true,
                  label: d.label,
                  // As in the dock: the tap the excluded ink would have given.
                  onTap: () => onSelected(i),
                  excludeSemantics: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(LunaTokens.radiusL),
                      onTap: () => onSelected(i),
                      child: extended
                          ? AnimatedContainer(
                              duration: Motion.of(context, Motion.medium),
                              height: controlHeight(context, 52),
                              padding: EdgeInsets.symmetric(horizontal: dense ? Space.m : Space.l),
                              decoration: BoxDecoration(
                                color: i == selected ? scheme.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    i == selected ? d.selectedIcon : d.icon,
                                    size: dense ? 22 : 24,
                                    color: i == selected
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: Space.m),
                                  Expanded(
                                    child: Text(
                                      d.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.labelLarge?.copyWith(
                                        color: i == selected ? scheme.onPrimary : scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: Space.xs),
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: Motion.of(context, Motion.medium),
                                    width: dense ? 52 : 60,
                                    height: dense ? 30 : 34,
                                    decoration: BoxDecoration(
                                      color: i == selected ? scheme.primary : Colors.transparent,
                                      borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
                                    ),
                                    child: Icon(
                                      i == selected ? d.selectedIcon : d.icon,
                                      size: dense ? 22 : 24,
                                      color: i == selected
                                          ? scheme.onPrimary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: Space.xxs),
                                  Text(
                                    d.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.labelMedium?.copyWith(color: scheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            if (onFold != null) ...[
              const Spacer(),
              Padding(
                padding: EdgeInsets.fromLTRB(extended ? Space.m : 0, 0, 0, Space.m),
                child: IconButton(
                  tooltip: extended ? t.nav.fold : t.nav.unfold,
                  onPressed: onFold,
                  // The caret points where the rail goes: left to fold it.
                  icon: Transform.flip(
                    flipX: extended,
                    child: Icon(AppIcons.chevron, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/map/presentation/sync_banner.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/adaptive_shell.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';

/// The height the search pill and the chips take over the map, below the
/// status bar.
const double _overlayHeight = 56 + Space.s + 60;

/// The map of places, in the three layouts: on a phone the map runs under the
/// status bar with the list and the details in a spring sheet; on a tablet
/// they open in a panel on the right; on a desktop the list, the map and the
/// details sit side by side.
class MapScreen extends ConsumerStatefulWidget {
  const new({this.placeId, super.key});

  /// A place to open on arrival, from a link.
  final String? placeId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openLinkedPlace());
    });
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    // After the build: a provider cannot change while widgets are updated.
    if (widget.placeId != old.placeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openLinkedPlace());
      });
    }
  }

  /// Selects the place a link names and, once the map is ready, shows it.
  Future<void> _openLinkedPlace() async {
    final id = widget.placeId;
    if (id == null) return;
    ref.read(selectionProvider.notifier).select(PlaceSelection(id));
    final place = await ref.read(placesRepositoryProvider).watchPlace(id).first;
    if (!mounted || place == null) return;
    // The map is ready once it reports its first camera: its style is loaded
    // and its size settled. A move sent before (the web map exists before it
    // is laid out) can land off centre.
    bool ready() => ref.read(mapControllerProvider) != null && ref.read(viewportProvider) != null;
    for (var i = 0; !ready() && i < 50 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    await ref.read(mapControllerProvider)?.moveTo(place.position, zoom: 13);
  }

  void _clearSelection() => ref.read(selectionProvider.notifier).select(null);

  @override
  Widget build(BuildContext context) {
    final size = WindowSize.of(context);
    final selection = ref.watch(selectionProvider);
    void locate() => unawaited(locateUser(context, ref));
    final body = switch (size) {
      .compact => _CompactLayout(selection: selection, onLocate: locate, onClose: _clearSelection),
      .medium => _MediumLayout(selection: selection, onLocate: locate, onClose: _clearSelection),
      .expanded => _ExpandedLayout(
        selection: selection,
        onLocate: locate,
        onClose: _clearSelection,
      ),
    };
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The status bar floats over the map: transparent, its icons in the
      // contrast of the theme's scrim.
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clearSelection},
        // The keyboard covers the map instead of squeezing it: the sheet and
        // the overlays keep their places, the search results end above it.
        child: Focus(autofocus: true, child: Scaffold(resizeToAvoidBottomInset: false, body: body)),
      ),
    );
  }
}

/// Whether the map gets zoom buttons: with a mouse, a pinch is not at hand.
bool get _pointerPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// The map itself, fed from the providers.
class _Map extends ConsumerWidget {
  const new({this.padding = EdgeInsets.zero, this.attributionInset = EdgeInsets.zero});

  final EdgeInsets padding;
  final EdgeInsets attributionInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final viewport = ref.read(viewportProvider);
    final places = ref.watch(mapPlacesProvider).value ?? const [];
    final selection = ref.watch(selectionProvider);
    final select = ref.read(selectionProvider.notifier);
    final map = ref.watch(lunaMapBuilderProvider)(
      context,
      LunaMapProps(
        style: style,
        dark: dark,
        initialCenter: viewport?.center ?? initialMapCenter,
        initialZoom: viewport?.zoom ?? initialMapZoom,
        places: places,
        selectedId: selection is PlaceSelection ? selection.id : null,
        markedPoint: selection is PointSelection ? selection.position : null,
        onPlaceTap: (id) => select.select(PlaceSelection(id)),
        onEmptyTap: () => select.select(null),
        onLongPress: (p) {
          select.select(PointSelection(p));
          // The sheet or panel that opens may cover the point: bring it into
          // the part of the map left free, at the same zoom.
          unawaited(ref.read(mapControllerProvider)?.moveTo(p));
        },
        onViewportChanged: (v) => ref.read(viewportProvider.notifier).update(v),
        onMapReady: (c) => ref.read(mapControllerProvider.notifier).attach(c),
        padding: padding,
        attributionInset: attributionInset,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        Positioned(
          left: attributionInset.left + Space.s + MapCredit.leading,
          // The credit's touch padding reaches below its label, which lines
          // up with the engines' own controls.
          bottom: attributionInset.bottom,
          child: const MapCredit(),
        ),
      ],
    );
  }
}

/// The soft fade under the status bar, so map labels never meet the clock.
class _TopScrim extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final scrim = LunaTokens.of(context).mapScrim;
    return IgnorePointer(
      child: Container(
        height: top + Space.huge,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scrim, scrim.withValues(alpha: 0)],
            stops: const [0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// The details of what is selected, for a sheet or a panel.
class _SelectionDetails extends StatelessWidget {
  const new({
    required this.selection,
    required this.onClose,
    this.scrollController,
    this.actions = false,
    this.bottomPadding = Space.huge,
    super.key,
  });

  final MapSelection selection;
  final VoidCallback onClose;
  final ScrollController? scrollController;
  final bool actions;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => switch (selection) {
    PlaceSelection(:final id) => PlaceDetails(
      placeId: id,
      scrollController: scrollController,
      onClose: onClose,
      actions: actions,
      bottomPadding: bottomPadding,
    ),
    PointSelection(:final position) => PointDetails(
      position: position,
      scrollController: scrollController,
      onClose: onClose,
      actions: actions,
      bottomPadding: bottomPadding,
    ),
  };
}

/// The action bar of what is selected, where the dock was on a phone.
class _SelectionActions extends ConsumerWidget {
  const new({required this.selection});

  final MapSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (selection) {
    PlaceSelection(:final id) => switch (ref.watch(placeProvider(id)).value) {
      final place? => PlaceActionBar(place: place, floating: true),
      null => const SizedBox.shrink(),
    },
    PointSelection(:final position) => PointActionBar(position: position, floating: true),
  };
}

/// The map's own buttons: the position, and zoom where there is a mouse.
class _MapControls extends StatelessWidget {
  const new({required this.onLocate, this.zoom = false});

  final VoidCallback onLocate;
  final bool zoom;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Consumer(
      builder: (context, ref, _) {
        final located = ref.watch(userLocationProvider) != null;
        final map = ref.watch(mapControllerProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (zoom) ...[
              FloatingSurface(
                radius: LunaTokens.radiusL,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: t.map.zoomIn,
                      icon: const Icon(AppIcons.zoomIn),
                      onPressed: map == null ? null : () => map.zoomBy(1),
                    ),
                    IconButton(
                      tooltip: t.map.zoomOut,
                      icon: const Icon(AppIcons.zoomOut),
                      onPressed: map == null ? null : () => map.zoomBy(-1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s),
            ],
            MapButton(
              icon: located ? AppIcons.locateActive : AppIcons.locate,
              tooltip: t.map.locateMe,
              onPressed: onLocate,
              size: 48,
            ),
          ],
        );
      },
    );
  }
}

/// Phone: the map under a transparent status bar, the search pill and the
/// chips floating at the top, and one spring sheet: the list resting low,
/// the details of a selection higher, with their actions where the dock
/// was.
class _CompactLayout extends ConsumerStatefulWidget {
  const new({required this.selection, required this.onLocate, required this.onClose});

  final MapSelection? selection;
  final VoidCallback onLocate;
  final VoidCallback onClose;

  @override
  ConsumerState<_CompactLayout> createState() => _CompactLayoutState();
}

class _CompactLayoutState extends ConsumerState<_CompactLayout> {
  final _sheet = SpringSheetController();
  double? _rest;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  // The list rests showing its count and one whole row above the dock.
  double _listPeek(MediaQueryData m) => 22 + 60 + 88 + m.padding.bottom;
  double _half(MediaQueryData m) => m.size.height * 0.52;
  double _full(MediaQueryData m) => m.size.height - m.padding.top - Space.s;

  // A selection opens high enough to show its name, its night and its
  // facts, and can be lowered to its header above the action bar.
  double _detailsPeek(MediaQueryData m) => 22 + 128 + m.padding.bottom;
  double _detailsOpen(MediaQueryData m) => m.size.height * 0.6;

  @override
  void didUpdateWidget(_CompactLayout old) {
    super.didUpdateWidget(old);
    if (old.selection != widget.selection) {
      final m = MediaQuery.of(context);
      final target = widget.selection == null ? _listPeek(m) : _detailsOpen(m);
      // The map centres what follows on the part the sheet will leave free,
      // not on the part it leaves free now.
      _rest = target;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sheet.animateTo(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = MediaQuery.of(context);
    final height = m.size.height;
    final selection = widget.selection;
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    final snaps = selection == null
        ? [_listPeek(m), _half(m), _full(m)]
        : [_detailsPeek(m), _detailsOpen(m), _full(m)];
    final rest = _rest ?? (selection == null ? _listPeek(m) : _detailsOpen(m));
    final top = m.padding.top + _overlayHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: _Map(
            padding: EdgeInsets.only(top: top, bottom: rest),
            attributionInset: EdgeInsets.only(left: Space.xs, bottom: rest),
          ),
        ),
        const Positioned(left: 0, right: 0, top: 0, child: _TopScrim()),
        const Positioned(
          left: Space.l,
          right: Space.l,
          top: 0,
          bottom: 0,
          child: Center(child: SyncBanner()),
        ),
        // The position button rides above the sheet, and steps aside when
        // the sheet rises over half the screen.
        if (!searching)
          ListenableBuilder(
            listenable: _sheet,
            builder: (context, _) {
              final extent = _sheet.isAttached ? _sheet.extent : rest;
              final hidden = extent > height * 0.58;
              return Positioned(
                right: Space.m,
                bottom: extent + Space.m,
                child: IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedOpacity(
                    duration: Motion.of(context, Motion.short),
                    opacity: hidden ? 0 : 1,
                    child: _MapControls(onLocate: widget.onLocate),
                  ),
                ),
              );
            },
          ),
        SpringSheet(
          controller: _sheet,
          snaps: snaps,
          initial: rest,
          onSettle: (v) => setState(() => _rest = v),
          onDismiss: selection == null ? null : widget.onClose,
          builder: (context, scroll) => AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: selection == null
                ? NearbyList(
                    key: const ValueKey('list'),
                    scrollController: scroll,
                    bottomPadding: m.padding.bottom + Space.l,
                    header: const Padding(
                      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                      child: NearbyCount(),
                    ),
                  )
                : _SelectionDetails(
                    key: ValueKey(selection),
                    selection: selection,
                    scrollController: scroll,
                    onClose: widget.onClose,
                    bottomPadding: m.padding.bottom + Space.xl,
                  ),
          ),
        ),
        // Where the dock was: the actions of the selection.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
              child: child,
            ),
            child: selection == null
                ? const SizedBox(key: ValueKey('none'), width: double.infinity)
                : OverMap(
                    key: ValueKey(selection),
                    // The bar takes the dock's place: the device's own inset
                    // only, not the room the shell keeps for the dock.
                    child: MediaQuery(
                      data: m.copyWith(
                        padding: m.padding.copyWith(
                          bottom: (m.padding.bottom - dockSpace).clamp(0, double.infinity),
                        ),
                      ),
                      child: _SelectionActions(selection: selection),
                    ),
                  ),
          ),
        ),
        // Above the sheet: the search results must cover it.
        ListenableBuilder(
          listenable: _sheet,
          builder: (context, child) {
            final extent = _sheet.isAttached ? _sheet.extent : rest;
            final covered = height - extent < m.padding.top + _overlayHeight;
            return Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: covered,
                child: AnimatedOpacity(
                  duration: Motion.of(context, Motion.short),
                  opacity: covered ? 0 : 1,
                  child: child,
                ),
              ),
            );
          },
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
                  child: MapSearch(),
                ),
                const QuickFilters(padding: EdgeInsets.fromLTRB(Space.m, Space.xxs, Space.xxl, 0)),
                if (!searching) const Center(child: IncompleteSyncNotice()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A rounded surface beside the map, holding the list or the details.
class _Panel extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FloatingSurface(
    radius: LunaTokens.radiusSheet,
    color: Theme.of(context).colorScheme.surface,
    child: AnimatedSwitcher(duration: Motion.of(context, Motion.medium), child: child),
  );
}

/// Tablet: the map beside the rail; the list and the details open in a
/// panel on the right.
class _MediumLayout extends ConsumerStatefulWidget {
  const new({required this.selection, required this.onLocate, required this.onClose});

  final MapSelection? selection;
  final VoidCallback onLocate;
  final VoidCallback onClose;

  @override
  ConsumerState<_MediumLayout> createState() => _MediumLayoutState();
}

class _MediumLayoutState extends ConsumerState<_MediumLayout> {
  bool _listOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final selection = widget.selection;
    final panelOpen = selection != null || _listOpen;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 720 ? 340.0 : 380.0;
    final reserved = panelOpen ? panelWidth + Space.xxl : 0.0;
    final top = MediaQuery.paddingOf(context).top + _overlayHeight;
    final count = ref.watch(nearbyPlacesProvider).value?.length;
    return Stack(
      children: [
        Positioned.fill(
          child: _Map(
            padding: EdgeInsets.only(right: reserved, top: top),
            attributionInset: const EdgeInsets.only(left: Space.s, bottom: Space.s),
          ),
        ),
        const Positioned(left: 0, right: 0, top: 0, child: _TopScrim()),
        Positioned(
          left: Space.l,
          right: Space.l + reserved,
          top: 0,
          bottom: 0,
          child: const Center(child: SyncBanner()),
        ),
        Positioned(
          right: reserved + Space.l,
          bottom: Space.l,
          child: _MapControls(onLocate: widget.onLocate, zoom: _pointerPlatform),
        ),
        // Above the buttons: the search results cover them.
        Positioned(
          left: Space.l,
          top: 0,
          right: reserved + Space.l,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Space.m),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: const MapSearch(),
                      ),
                    ),
                    if (!panelOpen) ...[
                      const SizedBox(width: Space.s),
                      FloatingSurface(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _listOpen = true),
                          icon: const Icon(AppIcons.list),
                          label: Text(
                            count == null ? t.map.showList : t.map.showListCount(n: count),
                          ),
                          style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
                        ),
                      ),
                    ],
                  ],
                ),
                const QuickFilters(
                  padding: EdgeInsets.only(top: Space.xxs, right: Space.xxl),
                ),
                const IncompleteSyncNotice(),
              ],
            ),
          ),
        ),
        AnimatedPositioned(
          duration: Motion.of(context, Motion.emphasized),
          curve: Motion.enter,
          top: 0,
          bottom: 0,
          right: panelOpen ? 0 : -panelWidth - Space.xxl,
          width: panelWidth + Space.m,
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, Space.m, Space.m, Space.m),
              child: _Panel(
                child: selection != null
                    ? _SelectionDetails(
                        key: ValueKey(selection),
                        selection: selection,
                        onClose: widget.onClose,
                        actions: true,
                      )
                    : NearbyList(
                        header: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.s, Space.s),
                          child: NearbyCount(
                            trailing: IconButton(
                              tooltip: t.common.close,
                              icon: const Icon(AppIcons.close),
                              onPressed: () => setState(() => _listOpen = false),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop: the list pane, the map, and the details pane side by side.
class _ExpandedLayout extends ConsumerWidget {
  const new({required this.selection, required this.onLocate, required this.onClose});

  final MapSelection? selection;
  final VoidCallback onLocate;
  final VoidCallback onClose;

  /// From this width the list stays beside the details; narrower, the
  /// details take the list's place so the map keeps room.
  static const threePanesFrom = 1500.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final paneWidth = width >= 1280 ? 420.0 : 380.0;
    final threePanes = width >= threePanesFrom;
    final selection = this.selection;
    final details = selection == null
        ? null
        : _SelectionDetails(
            key: ValueKey(selection),
            selection: selection,
            onClose: onClose,
            actions: true,
          );
    const list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
          child: MapSearch(floating: false),
        ),
        QuickFilters(padding: EdgeInsets.fromLTRB(Space.l, 0, Space.xxl, 0), floating: false),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.s),
          child: NearbyCount(),
        ),
        Divider(),
        Expanded(child: NearbyList()),
      ],
    );
    Widget pane(Widget child, {required bool left}) => Container(
      width: paneWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: left ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
          left: left ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: SafeArea(child: child),
    );
    return Row(
      children: [
        pane(
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            child: details != null && !threePanes
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.m),
                    child: details,
                  )
                : list,
          ),
          left: true,
        ),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(
                child: _Map(
                  attributionInset: EdgeInsets.only(left: Space.s, bottom: Space.s),
                ),
              ),
              const Positioned(
                left: Space.l,
                right: Space.l,
                top: 0,
                bottom: 0,
                child: Center(child: SyncBanner()),
              ),
              const Positioned(
                top: Space.l,
                left: 0,
                right: 0,
                child: Center(child: IncompleteSyncNotice()),
              ),
              Positioned(
                right: Space.l,
                bottom: Space.l,
                child: _MapControls(onLocate: onLocate, zoom: _pointerPlatform),
              ),
            ],
          ),
        ),
        if (threePanes)
          AnimatedSize(
            duration: Motion.of(context, Motion.emphasized),
            curve: Motion.enter,
            alignment: Alignment.centerLeft,
            child: details == null
                ? const SizedBox(height: double.infinity)
                : pane(
                    Padding(
                      padding: const EdgeInsets.only(top: Space.m),
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.medium),
                        child: details,
                      ),
                    ),
                    left: false,
                  ),
          ),
      ],
    );
  }
}

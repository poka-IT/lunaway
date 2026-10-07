import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/pointer_input.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/core/location/location_access.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/web/premap.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/camera_math.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/domain/map_taps.dart';
import 'package:lunaway/features/map/domain/place_tiles.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/map/presentation/map_credit.dart';
import 'package:lunaway/features/map/presentation/map_search.dart';
import 'package:lunaway/features/map/presentation/nearby_list.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/map/presentation/premap_spec.dart';
import 'package:lunaway/features/map/presentation/quick_filters.dart';
import 'package:lunaway/features/map/presentation/sync_banner.dart';
import 'package:lunaway/features/map/presentation/web_map_pointer.dart';
import 'package:lunaway/features/offline/application/offline_providers.dart';
import 'package:lunaway/features/offline/presentation/offline_notices.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/domain/poi_layer_view.dart';
import 'package:lunaway/features/poi/presentation/cheapest_fuel.dart';
import 'package:lunaway/features/poi/presentation/poi_details.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/adaptive_shell.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/floating.dart';
import 'package:lunaway/shared/widgets/measured.dart';
import 'package:lunaway/shared/widgets/over_map.dart';
import 'package:lunaway/shared/widgets/spring_sheet.dart';

final _log = Logger('map');

/// The height the search pill and the row of chips take over the map, below
/// the status bar.
double _overlayHeight(BuildContext context) =>
    mapOverlayHeight(Theme.of(context).visualDensity.baseSizeAdjustment.dy);

/// [_overlayHeight] for the density's size adjustment [dy] (0 to a finger,
/// -8 to a mouse), without a context: the web page's first map leaves the
/// same room (`premapDefaults`).
double mapOverlayHeight(double dy) =>
    MapSearch.touchHeight +
    dy +
    Space.s +
    Space.xxs +
    QuickFilters.chipTouchHeight +
    dy +
    Space.s * 2;

/// The search pill alone, while a selection hides the chips on a phone.
double _searchHeight(BuildContext context) => MapSearch.heightOf(context) + Space.s;

/// The list's pane beside the map of a wide window.
double mapPaneWidth(double windowWidth) => windowWidth >= mapPaneWideFrom ? 420 : 380;

/// The window width from which [mapPaneWidth] is the wider one.
const double mapPaneWideFrom = 1280;

/// How much of the list a phone shows over the map at rest, above the
/// bottom safe area: its handle, its count and one whole row.
const double mapListPeek = 22 + 60 + 88;

/// The room the first download's card needs on a phone with its picture;
/// with less, it goes without, so its buttons stay above the list.
const double _bannerWithPicture = 340;

/// The map of places, in the three layouts: on a phone the map runs under the
/// status bar with the list and the details in a spring sheet; on a tablet
/// they open in a panel on the right; on a desktop the list, the map and the
/// details sit side by side.
class MapScreen extends ConsumerStatefulWidget {
  const new({this.placeId, this.poiId, super.key});

  /// A place to open on arrival, from a link.
  final String? placeId;

  /// A shop or service to open on arrival, from a link.
  final String? poiId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.placeId != null || widget.poiId != null) {
        unawaited(_openLinkedPlace());
      } else {
        unawaited(
          _locateAtLaunch().catchError((Object e) => _log.info('no position at launch: $e')),
        );
      }
    });
  }

  /// With the position already allowed, the map opens on the user: the
  /// question at launch is where to sleep near here. It never asks for the
  /// position and says nothing when none comes; the web, whose browser
  /// would ask straight away, keeps the view it had.
  Future<void> _locateAtLaunch() async {
    if (kIsWeb || ref.read(userLocationProvider) != null) return;
    final access = await ref.read(locationPermissionsProvider).status();
    if (!mounted || access != LocationAccess.granted) return;
    // Ready once the map reports its first camera, after its first fit.
    bool ready() => ref.read(mapControllerProvider) != null && ref.read(viewportProvider) != null;
    for (var i = 0; !ready() && i < 50 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final controller = ref.read(mapControllerProvider);
    if (!mounted || controller == null) return;
    final before = ref.read(viewportProvider);
    final position = await controller.locateUser();
    if (!mounted || position == null) return;
    ref.read(userLocationProvider.notifier).update(position);
    // A place opened or the map moved by hand meanwhile keeps its camera.
    // The same camera reported again (its style loaded) is no move: only
    // the centre and the zoom count.
    final now = ref.read(viewportProvider);
    final moved =
        before == null ||
        now == null ||
        now.center.distanceTo(before.center) > 50 ||
        (now.zoom - before.zoom).abs() > 0.05;
    if (ref.read(selectionProvider) != null || moved) return;
    await controller.moveTo(position, zoom: 11);
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    // After the build: a provider cannot change while widgets are updated.
    if (widget.placeId != old.placeId || widget.poiId != old.poiId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openLinkedPlace());
      });
    }
  }

  /// Selects the place a link names and, once the map is ready, shows it.
  Future<void> _openLinkedPlace() async {
    if (widget.poiId != null) return await _openLinkedPoi(widget.poiId!);
    final id = widget.placeId;
    if (id == null) return;
    ref.read(selectionProvider.notifier).select(PlaceSelection(id));
    final Place? place;
    try {
      place = await ref.read(placeReaderProvider).watch(id).first;
    } on Object catch (e) {
      // Offline without a copy: the page says so.
      _log.info('linked place $id not read: $e');
      return;
    }
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

  /// The same for a shop or service, read from the API (or the copy kept
  /// when it was opened before).
  Future<void> _openLinkedPoi(String id) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final t = context.t;
    PoiFeature? feature;
    try {
      await for (final read in ref.read(poiRepositoryProvider).watchPage(id)) {
        // The last read wins: a point the server no longer has is gone,
        // whatever the copy said.
        feature = read.value?.poi.feature;
      }
    } on Object catch (e) {
      _log.info('linked point $id not read: $e');
    }
    if (!mounted) return;
    if (feature == null) {
      // No network and no copy, or gone from the map: said, rather than a
      // link that seems to do nothing.
      showMessage(messenger, t.poi.linkError);
      return;
    }
    ref.read(selectionProvider.notifier).select(PoiSelection(feature));
    bool ready() => ref.read(mapControllerProvider) != null && ref.read(viewportProvider) != null;
    for (var i = 0; !ready() && i < 50 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    await ref.read(mapControllerProvider)?.moveTo(feature.position, zoom: 15);
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
    final searching = ref.watch(searchQueryProvider).isNotEmpty;
    // The system back closes what lies over the map (the details, then the
    // search) before it may leave the app, as everywhere on Android.
    return PopScope(
      canPop: selection == null && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selection != null) {
          _clearSelection();
        } else {
          ref.read(searchQueryProvider.notifier).change('');
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // The status bar floats over the map: transparent, its icons in the
        // contrast of the theme's scrim.
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clearSelection},
          // The keyboard covers the map instead of squeezing it: the sheet
          // and the overlays keep their places, the search results end above
          // it.
          child: Focus(
            autofocus: true,
            child: Scaffold(resizeToAvoidBottomInset: false, body: body),
          ),
        ),
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
class _Map extends ConsumerStatefulWidget {
  const new({
    this.padding = EdgeInsets.zero,
    this.attributionInset = EdgeInsets.zero,
    this.onPlaceTapped,
  });

  final EdgeInsets padding;
  final EdgeInsets attributionInset;

  /// After a place's pin or a bare point was tapped and selected: the camera
  /// stays where it is, unlike a pick from a list, which moves it to the
  /// place.
  final VoidCallback? onPlaceTapped;

  @override
  ConsumerState<_Map> createState() => _MapState();
}

class _MapState extends ConsumerState<_Map> {
  /// A tap on bare map waits to know it is no double tap, which zooms.
  final _gate = DoubleTapGate();

  @override
  void dispose() {
    _gate.cancel();
    super.dispose();
  }

  /// A tap where nothing can be opened: closes what is open, or, at street
  /// level, marks the point and opens its card.
  void _onBareTap(LatLng at, double zoom) {
    _gate.tap(window: freeTapWindow(), () {
      if (!mounted) return;
      final select = ref.read(selectionProvider.notifier);
      switch (bareTapAt(zoom: zoom, open: ref.read(selectionProvider) != null)) {
        case BareTap.close:
          select.select(null);
        case BareTap.freePoint:
          select.select(PointSelection(at));
          widget.onPlaceTapped?.call();
        case BareTap.nothing:
          break;
      }
    });
  }

  /// The first time the map comes down to the street, one line says that a
  /// tap there leads somewhere; never again after.
  void _hintFreeTap(MapViewport v) {
    if (v.zoom < FreeTap.freePointMinZoom) return;
    final settings = ref.read(settingsProvider);
    if (settings.mapTapHintShown) return;
    unawaited(ref.read(settingsProvider.notifier).setMapTapHintShown());
    final t = context.t;
    showMessage(
      ScaffoldMessenger.maybeOf(context),
      pointerPlatform ? t.map.freeTapHintClick : t.map.freeTapHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final attributionInset = widget.attributionInset;
    final onPlaceTapped = widget.onPlaceTapped;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final viewport = ref.read(viewportProvider);
    final left = ref.read(initialViewProvider);
    // On the web the page's first map may still be on screen, where the user
    // may have moved it: the app's map opens on that camera.
    final premap = kIsWeb ? Premap.camera() : null;
    final language = Localizations.localeOf(context).languageCode;
    final filter = ref.watch(effectiveFilterProvider);
    void remember(MapViewport v) {
      if (!kIsWeb) return;
      Premap.remember(
        jsonEncode(
          premapState(
            basemapBase: ref.read(appConfigProvider).basemapBase,
            placesTileJson: ref.read(placeTileJsonUrlProvider),
            dark: dark,
            language: language,
            center: v.center,
            zoom: v.zoom,
            filter: filter,
          ),
        ),
      );
    }

    // A theme, a language or a filter changed: the next visit's first map
    // follows.
    if (kIsWeb && viewport != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remember(viewport));
    }
    // Online the places come from the tiles: the device's own places are
    // neither read nor turned into GeoJSON.
    final fromTiles = ref.watch(placesFromTilesProvider);
    final places = fromTiles
        ? const <PlaceSummary>[]
        : ref.watch(mapPlacesProvider).value ?? const <PlaceSummary>[];
    final selection = ref.watch(selectionProvider);
    final select = ref.read(selectionProvider.notifier);
    final poiChoice = ref.watch(poiLayerProvider);
    final pois = PoiLayerView(
      tileJsonUrl: ref.watch(poiTileJsonUrlProvider),
      category: poiChoice.category,
      vending: poiChoice.vending,
      openNowOnly: poiChoice.openNowOnly,
      state: ref.watch(poiLayerStateProvider),
      night: ref.watch(poiNightProvider),
      selected: selection is PoiSelection ? selection.feature : null,
      fuelLabels: poiChoice.category == PoiCategory.fuel
          ? ref.watch(fuelLabelsProvider(Localizations.localeOf(context).languageCode))
          : const [],
    );
    final map = ref.watch(lunaMapBuilderProvider)(
      context,
      LunaMapProps(
        style: style,
        dark: dark,
        // This run's last camera, else where the previous run left the map,
        // else France.
        initialCenter: premap?.center ?? viewport?.center ?? left?.center ?? initialMapCenter,
        initialZoom: premap?.zoom ?? viewport?.zoom ?? left?.zoom ?? initialMapZoom,
        places: places,
        placeTiles: fromTiles
            ? PlaceTilesView(tileJsonUrl: ref.watch(placeTileJsonUrlProvider), filter: filter)
            : null,
        selectedPlace: ref.watch(selectedPlaceProvider),
        markedPoint: selection is PointSelection ? selection.position : null,
        onPlaceTap: (id, {hint}) {
          _gate.cancel();
          select.select(PlaceSelection(id, hint: hint));
          onPlaceTapped?.call();
        },
        onPlacesInView: (places, bounds, {failed = false}) =>
            ref.read(placesInViewProvider.notifier).report(places, bounds, failed: failed),
        onEmptyTap: _onBareTap,
        onLongPress: (p) {
          _gate.cancel();
          select.select(PointSelection(p));
          // The sheet or panel that opens may cover the point: bring it into
          // the part of the map left free, at the same zoom.
          unawaited(ref.read(mapControllerProvider)?.moveTo(p));
        },
        onViewportChanged: (v) {
          ref.read(viewportProvider.notifier).update(v);
          _hintFreeTap(v);
          remember(v);
          unawaited(
            ref
                .read(lastViewStoreProvider)
                .save(v.center, v.zoom)
                .catchError((Object e) => _log.info('the view was not kept: $e')),
          );
          // A map at rest checks the basemap's host again when its last
          // answer is old: a lost network turns to the downloaded map.
          unawaited(ref.read(basemapReachabilityProvider.notifier).probeIfStale());
        },
        onMapReady: (c) => ref.read(mapControllerProvider.notifier).attach(c),
        padding: padding,
        attributionInset: attributionInset,
        language: Localizations.localeOf(context).languageCode,
        // The very first view shows the whole region below the search and
        // the chips; later ones come back where the user left the map, in
        // this run or the one before. A map made again before its fit (a
        // theme or language change in the first seconds) still fits: the
        // camera it reported is only the first one.
        fitInitial: premap == null && (viewport == null ? left == null : isFirstCamera(viewport)),
        pois: pois,
        onPoiTap: (feature) {
          _gate.cancel();
          select.select(PoiSelection(feature));
          // As for a long press: the sheet that opens may cover the point.
          unawaited(ref.read(mapControllerProvider)?.moveTo(feature.position));
        },
        onPoisInView: (features) => ref.read(poisInViewProvider.notifier).report(features),
      ),
    );
    final window = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (kIsWeb)
          // Where this map stands and the room its first fit leaves, for the
          // page's first map of the next visit (web/premap.js).
          ReportsRect(
            onRect: (rect) => Premap.rememberFrame(
              jsonEncode(
                premapFrame(
                  window: window,
                  map: rect,
                  fit: padding + const EdgeInsets.all(fitInitialMargin),
                ),
              ),
            ),
            child: MapShield(child: map),
          )
        else
          MapShield(child: map),
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
    PoiSelection(:final feature, :final from) => PoiDetails(
      feature: feature,
      from: from,
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
    PointSelection(:final position) => PointActionBar(
      position: position,
      floating: true,
      here: true,
    ),
    PoiSelection(:final feature) => PointActionBar(position: feature.position, floating: true),
  };
}

/// The map's own buttons: the position, and zoom where there is a mouse. A
/// new place starts from a tap on the map at street level, or a long press,
/// right where it goes.
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

  /// The notices under the search (offline, an unfinished download): the
  /// map keeps that room free too.
  double _notices = 0;

  /// The top of the map left free by the search, the chips and the notices.
  double _top(MediaQueryData m) =>
      m.padding.top +
      (widget.selection == null ? _overlayHeight(context) : _searchHeight(context)) +
      _notices;

  void _noticesChanged(double height) {
    if (!mounted || height == _notices) return;
    setState(() => _notices = height);
    _reveal();
  }

  /// Brings the selected place or point into the part of the map left free
  /// when the sheet or a notice covers its pin: a tap near the bottom opens
  /// the sheet over it, a notice appearing offline lands on it. Only after a
  /// tap on the map or a notice's change: a pick from the list, the search or the
  /// favourites moves the camera itself, with its own zoom.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selection = widget.selection;
      final viewport = ref.read(viewportProvider);
      if (viewport == null) return;
      final LatLng position;
      switch (selection) {
        case PlaceSelection(:final id):
          final place = ref.read(selectedPlaceProvider);
          if (place == null || place.id != id) return;
          position = place.position;
        case PointSelection(position: final at):
          position = at;
        case PoiSelection() || null:
          return;
      }
      final m = MediaQuery.of(context);
      final y = screenYOf(position, viewport.bounds, m.size.height);
      final bottom = m.size.height - (_rest ?? _detailsOpen(m));
      // The pin stands above its point: its head needs this much room.
      const pin = 52.0;
      if (y - pin >= _top(m) && y <= bottom - Space.m) return;
      unawaited(ref.read(mapControllerProvider)?.moveTo(position));
    });
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  // The list rests showing its count and one whole row above the dock.
  double _listPeek(MediaQueryData m) => mapListPeek + m.padding.bottom;
  double _half(MediaQueryData m) => m.size.height * 0.52;
  double _full(MediaQueryData m) => m.size.height - m.padding.top - Space.s;

  // A selection opens high enough to show its name, its night and its
  // facts, and can be lowered to its header above the action bar.
  double _detailsPeek(MediaQueryData m) => 22 + 128 + m.padding.bottom;
  double _detailsOpen(MediaQueryData m) => widget.selection is PointSelection
      // A bare point has little to say: its card opens just high enough for
      // its title, the new place and the coordinates, and the map keeps the
      // rest.
      ? math.min(m.size.height * 0.6, 22 + m.textScaler.scale(300) + m.padding.bottom)
      : m.size.height * 0.6;

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
    // With the fuel chip on, the sheet lists the cheapest stations around
    // in place of the places.
    final fuelList = ref.watch(poiLayerProvider).category == PoiCategory.fuel;
    final snaps = selection == null
        ? [_listPeek(m), _half(m), _full(m)]
        : [_detailsPeek(m), _detailsOpen(m), _full(m)];
    final rest = _rest ?? (selection == null ? _listPeek(m) : _detailsOpen(m));
    // While a sheet is open the chips give way: the map keeps the room above
    // the sheet for what was chosen.
    final top = _top(m);
    final clearance = MessageClearanceScope.maybeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: _Map(
            padding: EdgeInsets.only(top: top, bottom: rest),
            attributionInset: EdgeInsets.only(left: Space.xs, bottom: rest),
            onPlaceTapped: _reveal,
          ),
        ),
        const Positioned(left: 0, right: 0, top: 0, child: _TopScrim()),
        // The first download's card sits in the map left free, between the
        // chips and the sheet and clear of the map's buttons.
        Positioned(
          left: Space.l,
          right: Space.m + 48 + Space.s,
          top: top,
          bottom: rest,
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: SingleChildScrollView(
                child: SyncBanner(compact: true, picture: box.maxHeight >= _bannerWithPicture),
              ),
            ),
          ),
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
            child: selection == null && fuelList
                ? CheapestFuelList(
                    key: const ValueKey('fuel'),
                    scrollController: scroll,
                    bottomPadding: m.padding.bottom + Space.l,
                  )
                : selection == null
                ? NearbyList(
                    key: const ValueKey('list'),
                    scrollController: scroll,
                    bottomPadding: m.padding.bottom + Space.l,
                    header: const Padding(
                      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                      child: NearbyCount(),
                    ),
                  )
                : ListenableBuilder(
                    key: ValueKey(selection),
                    // The bar of actions grows with large text or a narrow
                    // screen: the details end above its measured top, so
                    // their last line is never under it.
                    listenable: clearance ?? const AlwaysStoppedAnimation<double>(0),
                    builder: (context, _) => _SelectionDetails(
                      selection: selection,
                      scrollController: scroll,
                      onClose: widget.onClose,
                      bottomPadding: math.max(m.padding.bottom, clearance?.value ?? 0) + Space.xl,
                    ),
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
                      child: Stack(
                        children: [
                          // The sheet's text fades under the bar and never
                          // shows between it and the edge.
                          const Positioned.fill(child: IgnorePointer(child: BottomFade())),
                          Padding(
                            padding: const EdgeInsets.only(top: BottomFade.lead),
                            child: _SelectionActions(selection: selection),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        // Above the sheet: the search results must cover it.
        ListenableBuilder(
          listenable: _sheet,
          builder: (context, child) {
            final extent = _sheet.isAttached ? _sheet.extent : rest;
            final covered = height - extent < m.padding.top + _overlayHeight(context);
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
                AnimatedSize(
                  duration: Motion.of(context, Motion.medium),
                  curve: Motion.enter,
                  alignment: Alignment.topCenter,
                  child: selection != null
                      ? const SizedBox(width: double.infinity)
                      : const QuickFilters(
                          padding: EdgeInsets.fromLTRB(Space.m, Space.xxs, Space.xxl, 0),
                        ),
                ),
                ReportsHeight(
                  onHeight: _noticesChanged,
                  child: searching
                      ? const SizedBox(width: double.infinity)
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(child: IncompleteSyncNotice()),
                            Center(child: OfflineMapNotice()),
                          ],
                        ),
                ),
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
    final top = MediaQuery.paddingOf(context).top + _overlayHeight(context);
    final page = ref.watch(nearbyPlacesPageProvider).value;
    final count = page?.total ?? page?.places.length;
    final fuelList = ref.watch(poiLayerProvider).category == PoiCategory.fuel;
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
                        // The rail beside it carries the brand.
                        child: const MapSearch(brand: false),
                      ),
                    ),
                    if (!panelOpen) ...[
                      const SizedBox(width: Space.s),
                      FloatingSurface(
                        child: TextButton.icon(
                          onPressed: () => setState(() => _listOpen = true),
                          icon: Icon(fuelList ? PoiLook.category(PoiCategory.fuel) : AppIcons.list),
                          label: Text(
                            fuelList
                                ? t.poi.cheapest.show
                                : count == null
                                ? t.map.showList
                                : t.map.showListCount(n: count),
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
                const OfflineMapNotice(),
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
                    : fuelList
                    ? CheapestFuelList(
                        topPadding: Space.l,
                        trailing: IconButton(
                          tooltip: t.common.close,
                          icon: const Icon(AppIcons.close),
                          onPressed: () => setState(() => _listOpen = false),
                        ),
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
    final paneWidth = mapPaneWidth(width);
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
    final fuelList = ref.watch(poiLayerProvider).category == PoiCategory.fuel;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
          child: MapSearch(floating: false),
        ),
        const QuickFilters(padding: EdgeInsets.fromLTRB(Space.l, 0, Space.xxl, 0), floating: false),
        if (fuelList) ...[
          const Divider(),
          const Expanded(child: CheapestFuelList(topPadding: Space.m)),
        ] else ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.xl, Space.xs, Space.xl, Space.s),
            child: NearbyCount(),
          ),
          const Divider(),
          const Expanded(child: NearbyList()),
        ],
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
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [IncompleteSyncNotice(), OfflineMapNotice()],
                  ),
                ),
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

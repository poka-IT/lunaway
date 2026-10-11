import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/pointer_input.dart';
import 'package:lunaway/core/location/browser_location.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/presentation/address_results.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('home');

/// What says where the home is, under its title: its address, led by its
/// name when the address does not begin with it ("Boulangerie du Lac ·
/// 3 rue du Port, Annecy"; an address alone once).
String homeLine(SavedPoint home) => switch (home.address) {
  null => home.name,
  final a when a.startsWith(home.name) => a,
  final a => '${home.name} · $a',
};

/// How to place the home on the map: a long press, or with a mouse its
/// right button, which does what a long press does.
String _onMapNotice(Translations t) =>
    pointerPlatform ? t.home.onMapNoticeClick : t.home.onMapNotice;

/// The route home: the preview, then the guidance, as for any destination,
/// named "Domicile"; its link names the home without its point.
void routeHome(BuildContext context, SavedPoint home) => openRoutePreview(
  context,
  RouteTarget(destination: home.position, label: context.t.home.title, home: true),
);

/// Makes [point] the home and says so, with the way back to the home
/// before (or to none).
Future<void> makeHome(BuildContext context, WidgetRef ref, SavedPoint point) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(homeRepositoryProvider);
  // Placed: the map's next point held is no longer offered as the home.
  ref.read(homePickingProvider.notifier).stop();
  try {
    final before = await repo.read();
    await repo.set(point);
    showMessage(
      messenger,
      before == null ? t.home.saved : t.home.changed,
      action: SnackBarAction(
        label: t.common.undo,
        onPressed: () => unawaited(before == null ? repo.clear() : repo.set(before)),
      ),
    );
  } on Object catch (e, s) {
    // The type alone: a database error's text holds the home.
    _log.warning('the home was not saved: ${e.runtimeType}', null, s);
    showMessage(messenger, t.common.saveFailed);
  }
}

/// Removes the home, with the way back.
Future<void> removeHome(BuildContext context, WidgetRef ref) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(homeRepositoryProvider);
  ref.read(homePickingProvider.notifier).stop();
  try {
    final before = await repo.read();
    if (before == null) return;
    await repo.clear();
    showMessage(
      messenger,
      t.home.removed,
      action: SnackBarAction(label: t.common.undo, onPressed: () => unawaited(repo.set(before))),
    );
  } on Object catch (e, s) {
    _log.warning('the home was not removed: ${e.runtimeType}', null, s);
    showMessage(messenger, t.common.saveFailed);
  }
}

/// What a place of the data becomes as a home: a point at its spot, named
/// as its card names it, with its town.
SavedPoint placeHomeDraft(Translations t, PlaceSummary place) => SavedPoint.normalized(
  id: savedPointIdAt(LatLng(place.lat, place.lon)),
  kind: SavedPointKind.point,
  name: t.summaryTitle(place),
  fallback: t.kind(place.kind),
  position: LatLng(place.lat, place.lon),
  address: [?place.street, ?place.city].join(', '),
);

/// The entry of a card's "…" menu about the home: "Définir comme domicile",
/// or, for the home itself, "Ce n'est plus mon domicile".
PopupMenuItem<T> homeEntry<T>(BuildContext context, T value, {required bool isHome}) =>
    PopupMenuItem<T>(
      value: value,
      child: ListTile(
        leading: const Icon(AppIcons.home),
        title: Text(isHome ? context.t.home.removeHere : context.t.home.setHere),
      ),
    );

/// What the entry of [homeEntry] does: [draft] becomes the home, or, when
/// it is the home already, the home goes.
Future<void> toggleHome(BuildContext context, WidgetRef ref, SavedPoint draft) async {
  final current = await ref.read(homeRepositoryProvider).read();
  if (!context.mounted) return;
  if (current != null && current.id == draft.id) {
    await removeHome(context, ref);
  } else {
    await makeHome(context, ref, draft);
  }
}

/// The device's position now, asked the considerate way the locate button
/// asks it; null, with a word, when none comes.
Future<LatLng?> currentPosition(BuildContext context, WidgetRef ref) async {
  final t = context.t;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final browser = ref.read(browserLocationProvider);
  // Read before anything is awaited: the sheet that asks may close
  // meanwhile, and its `ref` with it.
  final user = ref.read(userLocationProvider.notifier);
  if (browser != null) {
    // Asked before anything is awaited: a browser shows its prompt only
    // during the click.
    final fix = await browser.locate();
    switch (fix) {
      case BrowserPosition(:final position):
        user.update(position);
        return position;
      case BrowserDenied():
        showMessage(messenger, t.location.browserDenied);
      case BrowserNoFix():
        showMessage(messenger, t.location.browserNoFix);
    }
    return null;
  }
  final feed = ref.read(locationFeedProvider);
  if (!await ensureLocationAccess(context, ref)) return null;
  final fix = await feed.current();
  if (fix == null) {
    showMessage(messenger, t.location.noFix);
    return null;
  }
  user.update(fix.position);
  return fix.position;
}

/// The home at the head of the favourites: its pictogram, its name and
/// address, the route there in one tap, and its menu (see it on the map,
/// change it, remove it). Without a home, the way to set one.
class HomeCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final home = ref.watch(userHomeProvider);
    final point = home.value;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    if (home.hasError && !home.hasValue) {
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          child: Row(
            children: [
              Icon(AppIcons.home, color: scheme.error),
              const SizedBox(width: Space.ml),
              Expanded(
                child: Text(
                  t.home.error,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
              BusyButton(
                onPressed: () async => ref.invalidate(userHomeProvider),
                busy: home.isLoading,
                look: BusyLook.text,
                label: Text(t.common.retry),
              ),
            ],
          ),
        ),
      );
    }
    // Loading: the favourites screen shows its skeleton until the home is
    // read with the lists, so nothing moves down a frame later.
    if (!home.hasValue) return const SizedBox.shrink();
    final badge = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: point == null ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(44 * 0.32),
      ),
      child: Icon(
        AppIcons.home,
        size: 23,
        color: point == null ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
      ),
    );
    if (point == null) {
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
          onTap: () => showSetHomeSheet(context),
          // One line: the lists and their places keep the room of a phone
          // read at a large text size.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
            child: Row(
              children: [
                badge,
                const SizedBox(width: Space.ml),
                Expanded(
                  child: Text(t.home.setTitle, maxLines: 2, style: theme.textTheme.titleMedium),
                ),
                Icon(AppIcons.add, color: scheme.primary),
              ],
            ),
          ),
        ),
      );
    }
    final line = homeLine(point);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        onTap: () => _showOnMap(ref, point),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.xs, Space.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              badge,
              const SizedBox(width: Space.ml),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(t.home.title, style: theme.textTheme.titleMedium),
                    ),
                    Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    const SizedBox(height: Space.s),
                    // The card's one action, in one tap, under the text so
                    // a phone's width and a large text keep it whole.
                    FilledButton.icon(
                      onPressed: () => routeHome(context, point),
                      icon: const Icon(AppIcons.directions),
                      label: Text(t.place.directions, semanticsLabel: t.home.directionsHome),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                  ],
                ),
              ),
              _HomeMenu(home: point),
            ],
          ),
        ),
      ),
    );
  }
}

/// The home's card on the map, the map moved there.
void _showOnMap(WidgetRef ref, SavedPoint home) {
  ref.read(mapFlowProvider.notifier).openFromElsewhere(selectionOfSaved(home));
  unawaited(ref.read(mapControllerProvider)?.moveTo(home.position, zoom: 16));
}

class _HomeMenu extends ConsumerWidget {
  const new({required this.home});

  final SavedPoint home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return PopupMenuButton<String>(
      tooltip: t.home.actions,
      icon: const Icon(AppIcons.moreVertical),
      onSelected: (action) async {
        switch (action) {
          case 'map':
            _showOnMap(ref, home);
          case 'change':
            await showSetHomeSheet(context);
          case 'remove':
            await removeHome(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'map',
          child: ListTile(leading: const Icon(AppIcons.map), title: Text(t.favorites.openOnMap)),
        ),
        PopupMenuItem(
          value: 'change',
          child: ListTile(leading: const Icon(AppIcons.rename), title: Text(t.home.change)),
        ),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(leading: const Icon(AppIcons.delete), title: Text(t.home.remove)),
        ),
      ],
    );
  }
}

/// Where the home is: an address, a town or a place the search finds, the
/// device's position now, or a point the user holds on the map.
Future<void> showSetHomeSheet(BuildContext context) => showSheet<void>(
  context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (_) => const HomeSearch(),
);

/// The content of [showSetHomeSheet].
class HomeSearch extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeSearch> createState() => _HomeSearchState();
}

class _HomeSearchState extends ConsumerState<HomeSearch> {
  final _text = TextEditingController();
  String _query = '';
  bool _locating = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// [point] becomes the home, said where the sheet was opened.
  Future<void> _choose(SavedPoint point) async {
    final navigator = Navigator.of(context);
    await makeHome(context, ref, point);
    if (mounted) navigator.pop();
  }

  Future<void> _here() async {
    if (_locating) return;
    setState(() => _locating = true);
    final LatLng? position;
    try {
      position = await currentPosition(context, ref);
    } on Object catch (e) {
      _log.info('no position for the home: ${e.runtimeType}');
      if (mounted) setState(() => _locating = false);
      return;
    }
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) return;
    await _choose(pointDraft(context.t, position, now: ref.read(clockProvider)()));
  }

  /// The map, for a finger held where the home is; the card of that point
  /// offers "Mon domicile est ici".
  void _onMap() {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picking = ref.read(homePickingProvider.notifier);
    final flow = ref.read(mapFlowProvider.notifier);
    Navigator.of(context).pop();
    flow.openBareMapFromElsewhere();
    // Once the card open on the map, if any, has closed: closing it ends
    // the choice.
    picking.start();
    showMessage(messenger, _onMapNotice(t));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(userLocationProvider);
    final near = user ?? ref.read(viewportProvider)?.center;
    final language = t.$meta.locale.languageCode;
    final query = _query.trim();
    final results = query.isEmpty
        ? null
        : ref.watch(searchResultsProvider(query, near: near, language: language));
    // As the map's search: no address is asked offline nor under three
    // characters.
    final addresses = query.length < 3 || !ref.watch(placesFromTilesProvider)
        ? null
        : ref.watch(addressSearchProvider(query, near: near, language: language));
    final found = results?.value;
    final towns = found?.municipalities ?? const <Municipality>[];
    final places = found?.places ?? const <PlaceSummary>[];
    Widget icon(IconData data) => CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Icon(data),
    );
    Widget note(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: color ?? scheme.onSurfaceVariant),
      ),
    );
    return Padding(
      // Above the keyboard, which the field opens.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
            child: Semantics(
              header: true,
              child: Text(t.home.sheetTitle, style: theme.textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Text(
              t.home.privacy,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: TextField(
              controller: _text,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.home.searchHint,
                prefixIcon: const Icon(AppIcons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (results?.isLoading ?? false)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.m),
              children: [
                ListTile(
                  leading: icon(AppIcons.locate),
                  title: Text(t.home.myPosition),
                  trailing: _locating
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : null,
                  onTap: _here,
                ),
                ListTile(
                  leading: icon(AppIcons.point),
                  title: Text(t.home.onMap),
                  subtitle: Text(_onMapNotice(t)),
                  onTap: _onMap,
                ),
                // The API out of reach: the regions kept answer alone.
                if (found?.deviceOnly ?? false) note(t.search.deviceOnly),
                if (found != null && found.isEmpty) note(t.search.noResult(query: query)),
                if (results?.hasError ?? false) note(t.list.error, color: scheme.error),
                if (towns.isNotEmpty) SearchHeader(t.search.towns),
                for (final town in towns)
                  ListTile(
                    leading: icon(AppIcons.town),
                    title: Text(town.name),
                    subtitle: town.postcode == null ? null : Text(town.postcode!),
                    onTap: () => _choose(townDraft(t, town)),
                  ),
                if (places.isNotEmpty) SearchHeader(t.search.places),
                for (final place in places)
                  ListTile(
                    leading: icon(AppIcons.point),
                    title: Text(t.summaryTitle(place)),
                    subtitle: Text([t.kind(place.kind), ?place.city].join(' · ')),
                    onTap: () => _choose(placeHomeDraft(t, place)),
                  ),
                if (addresses != null)
                  AddressResults(
                    key: const ValueKey('addresses'),
                    addresses: addresses,
                    towns: towns,
                    from: user,
                    onTap: (address) => _choose(
                      pointDraft(
                        t,
                        address.position,
                        now: ref.read(clockProvider)(),
                        address: address,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// On the card of a point held on the map while the user places their
/// home: "Mon domicile est ici", and the way out of it.
class HomeHereButton extends ConsumerWidget {
  const new({required this.draft, super.key});

  /// The point as the home would keep it.
  final SavedPoint Function() draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(homePickingProvider)) return const SizedBox.shrink();
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                ref.read(homePickingProvider.notifier).stop();
                await makeHome(context, ref, draft());
              },
              icon: const Icon(AppIcons.home),
              label: Text(t.home.here),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ),
          const SizedBox(width: Space.s),
          TextButton(
            onPressed: () => ref.read(homePickingProvider.notifier).stop(),
            style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }
}

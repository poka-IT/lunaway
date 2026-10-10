import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/map/application/map_history.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_flow.g.dart';

/// What the map screen shows, in one model: the selection open (its card
/// or its panel), with the way back through the selections
/// ([SelectionTrail]), and the count of the changes it has seen
/// ([revision]). The search's text and the pages over the map (the route
/// preview, the guidance) live where they are typed and shown, but every
/// change of them goes through [MapFlow] as well.
@immutable
final class MapFlowState {
  const new({this.trail = const SelectionTrail(), this.revision = 0});

  /// The selections the back walks through, the last one open.
  final SelectionTrail trail;

  /// Moves on at every change of what the map screen shows: a selection,
  /// the search opened or closed, a page opened over the map or left, an
  /// address the browser came back to, another tab. A change that began
  /// under an older revision came after something else and is dropped.
  final int revision;

  /// What is open: a place, a point of interest, a point, or nothing.
  MapSelection? get selection => trail.current;
}

/// Every change of what the map screen shows is asked of this one model,
/// whatever asks and in whichever layout: a pin, a row of a list, a search
/// result, a card's close, Escape, the system back, the browser's back or
/// forward, a link, the favourites, a page opened over the map or left. It
/// decides the change, keeps the way back, and has the tab's history
/// written by [MapHistory], the one writer.
///
/// A change that comes late is held to what happened since it began. A
/// tap on the map acts a moment after its press (it waits to know it is
/// no double tap), and a link is read before it opens: the user may have
/// opened something else meanwhile. Such a change carries the
/// [MapFlowState.revision] it began under (`since`) and is dropped when anything changed since:
/// it never undoes a newer action of the user.
// keepAlive: what is open stays through a switch to another tab and the
// pages over the map, as the history of the tab does.
@Riverpod(keepAlive: true)
class MapFlow extends _$MapFlow {
  @override
  MapFlowState build() {
    // The search opened or closed changes what the map shows: a tap on the
    // map pressed before it is out of date.
    ref.listen(searchQueryProvider.select((q) => q.trim().isEmpty), (_, _) => _touch());
    return const MapFlowState();
  }

  MapHistory get _history => ref.read(mapHistoryProvider);

  void _touch() => state = MapFlowState(trail: state.trail, revision: state.revision + 1);

  void _set(SelectionTrail trail) =>
      state = MapFlowState(trail: trail, revision: state.revision + 1);

  /// Whether nothing changed since [revision] ([MapFlowState.revision]).
  bool stands(int revision) => state.revision == revision;

  /// The user chose [next] on the map screen; null closes what is open.
  /// [since]: the revision under which the gesture behind the choice began
  /// (a press on the map); a choice that began before the last change is
  /// dropped. Returns whether the choice was made.
  ///
  /// A selection opened from the open one (a shop of a place's
  /// surroundings) is a step further, so back returns to the place. Any
  /// other replaces what is open, so one back closes it. In a browser each
  /// step has an entry of the tab's history, its address a link to share.
  bool select(MapSelection? next, {int? since}) {
    if (since != null && !stands(since)) return false;
    final before = state.trail;
    if (next != null && next == before.current) {
      // Chosen again: its page goes back to its top.
      ref.read(reselectionsProvider.notifier).bump();
      _set(before.withCurrent(next));
      return true;
    }
    final (trail, step) = before.follow(next, onBareMap: _history.onBareMap);
    _set(trail);
    _write(step, next);
    return true;
  }

  /// What the tab's history does for [step], which opened [next].
  void _write(TrailStep step, MapSelection? next) {
    final history = _history;
    if (!history.writesAddresses) return;
    final link = MapLink.to(next);
    switch (step) {
      case TrailStay():
        break;
      case TrailPush() || TrailLeave():
        history.pushMap(link);
      case TrailReplace():
        history.replaceMap(link);
      case TrailBack(:final steps):
        if (history.onOwnEntry) {
          history.back(steps);
        } else {
          // The map did not write the entry shown: what lies under it is
          // not known, and going back could land anywhere (it once landed
          // on a guidance left behind the map). What is open now takes an
          // entry of its own, and the way back starts again from it.
          state = MapFlowState(trail: SelectionTrail.adopt(next), revision: state.revision);
          history.pushMap(link);
        }
    }
  }

  /// The system back on the map screen (the apps: a browser's back moves
  /// its history, [arrived]): the selection the open one was opened from,
  /// or none; with nothing open, the search closes. False when there is
  /// nothing to close: the back may then leave.
  bool back() {
    if (state.selection != null) return select(state.trail.previous);
    final search = ref.read(searchQueryProvider.notifier);
    if (ref.read(searchQueryProvider).isEmpty) return false;
    search.change('');
    return true;
  }

  /// The list of the places around what is open, in place of its card, in
  /// every layout: the card closes and the list opens where it is folded
  /// away (the tablet's panel, [PlacesAroundAsked]).
  void showPlacesAround() {
    select(null);
    ref.read(placesAroundAskedProvider.notifier).bump();
  }

  /// The browser came back or forward to [link], on the map. Returns the
  /// link when the way back holds no such step (a link from elsewhere, a
  /// page reloaded): the screen reads what it names and opens it
  /// ([adopt]).
  MapLink? arrived(MapLink link) {
    final trail = state.trail;
    if (link.names(trail.current)) return null;
    if (trail.arrive(link) case (final there, _)?) {
      _set(there);
      return null;
    }
    if (link.point) {
      // A point is not written in the address: this session no longer
      // knows which one it was.
      _set(const SelectionTrail());
      _history.replaceMap(MapLink.none);
      return null;
    }
    _touch();
    return link;
  }

  /// The map was left for another tab: the steps under what is open are
  /// no longer under the entry the map comes back on.
  void detach() => _set(state.trail.detached());

  /// What a link names, opened ([selection], or nothing it could open):
  /// the way back starts again from it. Returns the revision it opened
  /// under; the camera's move that follows the link's read is made only
  /// while it [stands].
  int adopt(MapSelection? selection) {
    _set(SelectionTrail.adopt(selection));
    return state.revision;
  }

  /// In a browser, the address of [selection], what is open, in place of a
  /// link that opened nothing; the way back starts again from it.
  void showAddressOf(MapSelection? selection) {
    _set(SelectionTrail.adopt(selection));
    _history.replaceMap(MapLink.to(selection));
  }

  /// [selection] chosen on another tab (the favourites): the map opens at
  /// its own address, on a new entry; the bare map's would close it.
  void openFromElsewhere(MapSelection selection) {
    select(selection);
    _history.goToMap(MapLink.to(selection));
  }

  /// A page opened over the map (the route preview), on the entry above
  /// the map's.
  void openPage(String location, {Object? extra}) {
    _touch();
    _history.pushPage(location, extra: extra);
  }

  /// [location] in place of the page over the map (the guidance after its
  /// preview), on that page's entry.
  void replacePage(String location, {Object? extra}) {
    _touch();
    _history.replacePage(location, extra: extra);
  }

  /// The page over the map left for the map under it.
  void leavePage() {
    _touch();
    _history.leavePage();
  }
}

/// How many times the list of the places around was asked for
/// ([MapFlow.showPlacesAround]): a layout that folds its list away opens
/// it at each.
// keepAlive: a count of the run, which a layout built later must not take
// for a new request.
@Riverpod(keepAlive: true)
class PlacesAroundAsked extends _$PlacesAroundAsked {
  @override
  int build() => 0;

  void bump() => state++;
}

/// What the map points at: a place, a point the user long-pressed or an
/// address the search found, or a point of interest; null for none. Read
/// only: it changes through [MapFlow].
// keepAlive: it follows the flow, itself kept.
@Riverpod(keepAlive: true)
MapSelection? selection(Ref ref) => ref.watch(mapFlowProvider).selection;

import 'package:flutter/foundation.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selection_trail.g.dart';

/// What the address of the map names: nothing, a place
/// (`/map?place=<id>`), a point of interest (`/map?poi=<id>`, with
/// `&from=<place id>` when it was opened from a place's surroundings), or a
/// point (`/map?point`). A place and a point of interest make links to share
/// and pages to bookmark; a point keeps its coordinates out of the address,
/// which the browser's history would keep, and opens again from this
/// session's memory only.
@immutable
final class MapLink {
  const new({this.place, this.poi, this.from, this.point = false});

  /// What the address [uri] names; nothing for any other page than the map.
  factory of(Uri uri) {
    if (uri.path != AppRoutes.map) return none;
    final q = uri.queryParameters;
    String? id(String key) => switch (q[key]) {
      final v? when v.isNotEmpty => v,
      _ => null,
    };
    if (id('place') case final place?) return MapLink(place: place);
    if (id('poi') case final poi?) return MapLink(poi: poi, from: id('from'));
    if (q.containsKey('point')) return const MapLink(point: true);
    return none;
  }

  /// The address of [selection].
  factory to(MapSelection? selection) => switch (selection) {
    null => none,
    PlaceSelection(:final id) => MapLink(place: id),
    PoiSelection(:final feature, :final from) => MapLink(poi: feature.id, from: from),
    PointSelection() => const MapLink(point: true),
  };

  /// The map with nothing open.
  static const none = MapLink();

  final String? place;
  final String? poi;

  /// The place a point of interest was opened from, to go back to.
  final String? from;
  final bool point;

  bool get isNone => place == null && poi == null && !point;

  /// The location the router shows for this link.
  String get location {
    final query = <String, String>{
      'place': ?place,
      'poi': ?poi,
      'from': ?from,
      if (point) 'point': '',
    };
    return Uri(path: AppRoutes.map, queryParameters: query.isEmpty ? null : query).toString();
  }

  /// Whether [selection] is what this link names.
  bool names(MapSelection? selection) => switch (selection) {
    null => isNone,
    PlaceSelection(:final id) => place == id,
    PoiSelection(:final feature, from: final origin) => poi == feature.id && from == origin,
    PointSelection() => point,
  };

  @override
  bool operator ==(Object other) =>
      other is MapLink &&
      other.place == place &&
      other.poi == poi &&
      other.from == from &&
      other.point == point;

  @override
  int get hashCode => Object.hash(place, poi, from, point);

  @override
  String toString() => location;
}

/// The mark the map writes, through the router's `extra`, in the state of
/// every entry of the tab's history it makes for its selections. The
/// browser keeps it with the entry and gives it back when it returns there.
///
/// The way back walks the history only from an entry holding one of this
/// page's marks: any other was written by something else (a link, the
/// favourites, an earlier load of the page), and what lies under it is not
/// known. The route preview and the guidance hold the entry above the
/// map's and leave by the browser's back (`leaveForMap`), so the map comes
/// back on its own marked entry.
///
/// What a mark cannot tell: go_router copies the map's `extra` into the
/// state of every page pushed over it, so a page over the map popped by
/// the app would write the map again, mark included, on a new entry above
/// its own, and the way back would take that copy for the map's entry. A
/// page pushed over the map leaves only through `leaveForMap`.
abstract final class TrailMarks {
  static const _key = 'lunawayTrail';

  /// This load of the page: a mark kept by the history from an earlier
  /// load is not one of ours.
  static final String _page = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  static int _count = 0;

  /// A new mark, as the router's `extra`: plain JSON, which the history
  /// stores as it is.
  static Map<String, String> next() => {_key: '$_page-${++_count}'};

  /// Whether [extra], read from the router, is a mark of this page.
  static bool ours(Object? extra) =>
      extra is Map && extra[_key] is String && (extra[_key] as String).startsWith('$_page-');
}

/// What a change of the selection does to the way back.
@immutable
sealed class TrailStep {
  const new();
}

/// Nothing: the selection is the one the way back already shows.
final class TrailStay extends TrailStep {
  const new();
}

/// A new step: what was open stays one back away.
final class TrailPush extends TrailStep {
  const new();
}

/// The step taken by what was open goes to what opens instead.
final class TrailReplace extends TrailStep {
  const new();
}

/// Back [steps] steps, to what was open before.
final class TrailBack extends TrailStep {
  const new(this.steps);

  final int steps;

  @override
  bool operator ==(Object other) => other is TrailBack && other.steps == steps;

  @override
  int get hashCode => steps.hashCode;
}

/// A new step to the map with nothing open: the way back from here does
/// not lead to it (the map was reached from a link or another page).
final class TrailLeave extends TrailStep {
  const new();
}

/// The selections the back gesture walks through, oldest first, the last
/// one open. On the web each has an entry of its own in the browser's
/// history, above the map with nothing open; a native back reopens the one
/// under the open one, or closes it.
///
/// A selection opened from the open one (a shop of a place's surroundings)
/// is a new step, so back returns to the place. Any other change replaces
/// the open one: the way back stays one step deep, and back closes what is
/// open as on Android everywhere.
@immutable
final class SelectionTrail {
  const new({this.entries = const [], this.ahead = const [], this.based = true});

  /// A trail that starts again from [selection], opened from an address the
  /// trail did not know: what lies under it in the browser's history is not
  /// the map.
  factory adopt(MapSelection? selection) => selection == null
      ? const SelectionTrail()
      : SelectionTrail(entries: [selection], based: false);

  /// The selections with a step of their own, oldest first.
  final List<MapSelection> entries;

  /// The selections a back closed, which a forward reopens, nearest first.
  final List<MapSelection> ahead;

  /// Whether the map with nothing open lies one step under [entries]: a
  /// close then goes back to it. Not when the map opened on a link, or was
  /// left for another tab meanwhile.
  final bool based;

  /// What is open.
  MapSelection? get current => entries.isEmpty ? null : entries.last;

  /// What a back reopens: the selection under [current], or nothing.
  MapSelection? get previous => entries.length < 2 ? null : entries[entries.length - 2];

  /// The selection became [next] by the user's hand. [onBareMap] says
  /// whether the map with nothing open is what the way back shows now, for
  /// a first step.
  (SelectionTrail, TrailStep) follow(MapSelection? next, {bool onBareMap = true}) {
    if (next == current) return (this, const TrailStay());
    if (next == null) {
      if (!based) return (const SelectionTrail(), const TrailLeave());
      return (SelectionTrail(ahead: [...entries, ...ahead]), TrailBack(entries.length));
    }
    final under = entries.indexOf(next);
    if (under >= 0) {
      return (
        SelectionTrail(
          entries: entries.sublist(0, under + 1),
          ahead: [...entries.sublist(under + 1), ...ahead],
          based: based,
        ),
        TrailBack(entries.length - 1 - under),
      );
    }
    final open = current;
    if (open == null) {
      return (SelectionTrail(entries: [next], based: onBareMap), const TrailPush());
    }
    if (opensFrom(next, open)) {
      return (SelectionTrail(entries: [...entries, next], based: based), const TrailPush());
    }
    return (
      SelectionTrail(
        entries: [...entries.sublist(0, entries.length - 1), next],
        ahead: ahead,
        based: based,
      ),
      const TrailReplace(),
    );
  }

  /// The browser moved back or forward to an address naming [link]. Returns
  /// the trail at that step and the selection it shows there, or null when
  /// the trail holds no such step (a link from elsewhere, a page reloaded):
  /// the caller opens the link and starts a trail from it
  /// ([SelectionTrail.adopt]).
  (SelectionTrail, MapSelection?)? arrive(MapLink link) {
    if (link.names(current)) return (this, current);
    if (link.isNone) {
      return based
          ? (SelectionTrail(ahead: [...entries, ...ahead]), null)
          : (const SelectionTrail(), null);
    }
    for (var i = entries.length - 2; i >= 0; i--) {
      if (link.names(entries[i])) {
        return (
          SelectionTrail(
            entries: entries.sublist(0, i + 1),
            ahead: [...entries.sublist(i + 1), ...ahead],
            based: based,
          ),
          entries[i],
        );
      }
    }
    for (var j = 0; j < ahead.length; j++) {
      if (link.names(ahead[j])) {
        return (
          SelectionTrail(
            entries: [...entries, ...ahead.sublist(0, j + 1)],
            ahead: ahead.sublist(j + 1),
            based: based,
          ),
          ahead[j],
        );
      }
    }
    return null;
  }

  /// The map was left for another tab: the steps under [current] are no
  /// longer under what the browser shows when the map comes back.
  SelectionTrail detached() => SelectionTrail.adopt(current);

  /// Whether [next] opens from [open], one step further: a point of interest
  /// from the surroundings of the place open.
  static bool opensFrom(MapSelection next, MapSelection open) =>
      next is PoiSelection && open is PlaceSelection && next.from == open.id;
}

/// The way back through the selections of the map.
// keepAlive: it follows the selection (itself kept) through tab switches and
// the screens over the map.
@Riverpod(keepAlive: true)
class MapTrail extends _$MapTrail {
  @override
  SelectionTrail build() => const SelectionTrail();

  void set(SelectionTrail trail) => state = trail;
}

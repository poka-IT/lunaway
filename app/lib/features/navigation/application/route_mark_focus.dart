import 'package:flutter/foundation.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'route_mark_focus.g.dart';

/// Which marks of the preview's map and rows of its list go together right
/// now: the pointer over a mark lights its row, the pointer over a row
/// lights its marks, a chosen row brings its marks into view, a chosen mark
/// brings its row into view.
@immutable
final class MarkFocus {
  const new({
    this.hovered = const {},
    this.selected,
    this.flight,
    this.flightSerial = 0,
    this.reveal,
    this.revealSerial = 0,
  });

  /// The marks under the pointer, on the map or through a row.
  final Set<String> hovered;

  /// The mark last clicked or tapped.
  final String? selected;

  /// The marks a row asked the map to show; [flightSerial] counts the
  /// requests, so the same row asked twice flies twice.
  final List<String>? flight;
  final int flightSerial;

  /// The mark whose row the list is asked to show.
  final String? reveal;
  final int revealSerial;

  /// The marks drawn lit.
  Set<String> get lit => {...hovered, ?selected};

  @override
  bool operator ==(Object other) =>
      other is MarkFocus &&
      setEquals(other.hovered, hovered) &&
      other.selected == selected &&
      listEquals(other.flight, flight) &&
      other.flightSerial == flightSerial &&
      other.reveal == reveal &&
      other.revealSerial == revealSerial;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(hovered),
    selected,
    flight == null ? null : Object.hashAll(flight!),
    flightSerial,
    reveal,
    revealSerial,
  );
}

/// The focus of the marks of the preview of [target].
@riverpod
class RouteMarkFocus extends _$RouteMarkFocus {
  @override
  MarkFocus build(RouteTarget target) => const MarkFocus();

  /// The pointer came over [ids] (a mark, or the row of several), or left
  /// them (empty).
  void hover(Set<String> ids) {
    if (setEquals(ids, state.hovered)) return;
    state = _copy(hovered: ids);
  }

  /// The pointer left [ids]; another hover that came since stays.
  void leave(Set<String> ids) {
    if (!setEquals(ids, state.hovered)) return;
    state = _copy(hovered: const {});
  }

  /// A mark was clicked or tapped; null clears the choice.
  void select(String? id) {
    if (id == state.selected) return;
    state = _copy(selected: id, clearSelected: id == null);
  }

  /// A row was chosen: the map shows and pulses its marks.
  void fly(List<String> ids) {
    if (ids.isEmpty) return;
    state = _copy(flight: ids, flightSerial: state.flightSerial + 1);
  }

  /// A mark asked for its row: the list scrolls to it.
  void reveal(String id) {
    state = _copy(selected: id, reveal: id, revealSerial: state.revealSerial + 1);
  }

  /// Another route was chosen: its marks are others.
  void clear() =>
      state = MarkFocus(flightSerial: state.flightSerial, revealSerial: state.revealSerial);

  MarkFocus _copy({
    Set<String>? hovered,
    String? selected,
    bool clearSelected = false,
    List<String>? flight,
    int? flightSerial,
    String? reveal,
    int? revealSerial,
  }) => MarkFocus(
    hovered: hovered ?? state.hovered,
    selected: clearSelected ? null : selected ?? state.selected,
    flight: flight ?? state.flight,
    flightSerial: flightSerial ?? state.flightSerial,
    reveal: reveal ?? state.reveal,
    revealSerial: revealSerial ?? state.revealSerial,
  );
}

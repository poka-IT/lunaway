import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where something [width] wide goes across a room from [lo] to [hi]:
/// centred on [centre], moved only as far as it must to stay inside the
/// room, and narrowed to the room when it is wider. The left edge and the
/// width it gets.
///
/// The rule of every element meant to be centred over a screen or a map
/// (a button, a card, a message): it centres on the whole area, never on
/// what a column of buttons or a panel leaves of it, so that it does not
/// sit off centre when it would fit; those only push it aside when it would
/// cover them.
({double left, double width}) centredSpan({
  required double centre,
  required double width,
  required double lo,
  required double hi,
}) {
  final room = math.max<double>(0, hi - lo);
  final w = math.min(width, room);
  return (left: (centre - w / 2).clamp(lo, lo + room - w), width: w);
}

/// The room a column of buttons, a panel or a camera cut-out takes from one
/// side of a [CentredClear], the gap to keep from it included.
@immutable
final class SideRoom {
  /// [width] from the left edge: over the whole height, or with [height]
  /// over that much from the bottom edge up.
  const new left(this.width, {this.height}) : right = false;

  /// [width] from the right edge, as [SideRoom.left].
  const new right(this.width, {this.height}) : right = true;

  final double width;
  final double? height;

  /// Taken from the right edge, else from the left one.
  final bool right;

  @override
  bool operator ==(Object other) =>
      other is SideRoom && other.width == width && other.height == height && other.right == right;

  @override
  int get hashCode => Object.hash(width, height, right);

  @override
  String toString() => 'SideRoom.${right ? 'right' : 'left'}($width, height: $height)';
}

/// Lays [child] out centred on the whole width it is given, the screen or
/// the map beside a fixed panel, and moves it aside only as far as it must
/// to stay off [obstacles] ([centredSpan]): a button that a column of
/// buttons would cover shifts by the overlap, one that clears it stays in
/// the middle. [margin] is the least room kept from the edges.
///
/// A room over a band of the height ([SideRoom.height]) counts only when
/// the child reaches down into that band: a card above a corner button
/// keeps the middle.
///
/// The child is as wide as it likes up to the room left between the edges
/// and the rooms that always count; narrowed further only when a band it
/// reaches leaves less. Height: with [heightFactor] null, all the height
/// given when it is bounded, the child centred in it; else as tall as the
/// child (with 1, as `Center(heightFactor: 1)`).
class CentredClear extends SingleChildRenderObjectWidget {
  const new({
    this.margin = EdgeInsets.zero,
    this.obstacles = const [],
    this.heightFactor,
    super.child,
    super.key,
  });

  final EdgeInsets margin;
  final List<SideRoom> obstacles;
  final double? heightFactor;

  @override
  RenderCentredClear createRenderObject(BuildContext context) =>
      RenderCentredClear(margin: margin, obstacles: obstacles, heightFactor: heightFactor);

  @override
  void updateRenderObject(BuildContext context, RenderCentredClear renderObject) => renderObject
    ..margin = margin
    ..obstacles = obstacles
    ..heightFactor = heightFactor;
}

/// The layout of [CentredClear].
class RenderCentredClear extends RenderShiftedBox {
  new({required this._margin, required this._obstacles, this._heightFactor, RenderBox? child})
    : super(child);

  EdgeInsets _margin;
  EdgeInsets get margin => _margin;
  set margin(EdgeInsets value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsLayout();
  }

  List<SideRoom> _obstacles;
  List<SideRoom> get obstacles => _obstacles;
  set obstacles(List<SideRoom> value) {
    if (listEquals(value, _obstacles)) return;
    _obstacles = value;
    markNeedsLayout();
  }

  double? _heightFactor;
  double? get heightFactor => _heightFactor;
  set heightFactor(double? value) {
    if (value == _heightFactor) return;
    _heightFactor = value;
    markNeedsLayout();
  }

  /// Whether this box takes the whole height it is given.
  bool get _fills => _heightFactor == null && constraints.hasBoundedHeight;

  /// The room between the edges and [rooms], for a box [width] wide.
  (double, double) _room(double width, Iterable<SideRoom> rooms) {
    var lo = margin.left;
    var hi = width - margin.right;
    for (final r in rooms) {
      if (r.right) {
        hi = math.min(hi, width - r.width);
      } else {
        lo = math.max(lo, r.width);
      }
    }
    return (lo, math.max(lo, hi));
  }

  BoxConstraints _childConstraints(double room) => BoxConstraints(
    maxWidth: room,
    maxHeight: constraints.hasBoundedHeight
        ? math.max(0, constraints.maxHeight - margin.vertical)
        : double.infinity,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (_heightFactor == null && constraints.hasBoundedHeight) {
      return constraints.constrain(Size(width, constraints.maxHeight));
    }
    final (lo, hi) = _room(width, obstacles.where((r) => r.height == null));
    final child = this.child?.getDryLayout(_childConstraints(hi - lo)) ?? Size.zero;
    return constraints.constrain(
      Size(width, child.height * (_heightFactor ?? 1) + margin.vertical),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    final width = constraints.maxWidth;
    if (child == null) {
      size = constraints.constrain(Size(width, _fills ? constraints.maxHeight : 0));
      return;
    }
    var (lo, hi) = _room(width, obstacles.where((r) => r.height == null));
    child.layout(_childConstraints(hi - lo), parentUsesSize: true);
    double heightFor(Size child) => _fills
        ? constraints.maxHeight
        : constraints.constrainHeight(child.height * (_heightFactor ?? 1) + margin.vertical);
    double topFor(Size child, double height) =>
        margin.top + (height - margin.vertical - child.height) / 2;
    var height = heightFor(child.size);
    // The rooms of a band push the child aside only when it reaches into
    // them; narrower, it may then grow taller, and is placed again.
    final reached = [
      for (final r in obstacles)
        if (r.height case final band?
            when topFor(child.size, height) + child.size.height > height - band)
          r,
    ];
    if (reached.isNotEmpty) {
      (lo, hi) = _room(width, [...obstacles.where((r) => r.height == null), ...reached]);
      if (child.size.width > hi - lo) {
        child.layout(_childConstraints(hi - lo), parentUsesSize: true);
        height = heightFor(child.size);
      }
    }
    size = constraints.constrain(Size(width, height));
    final span = centredSpan(centre: size.width / 2, width: child.size.width, lo: lo, hi: hi);
    (child.parentData! as BoxParentData).offset = Offset(
      span.left,
      topFor(child.size, size.height),
    );
  }
}

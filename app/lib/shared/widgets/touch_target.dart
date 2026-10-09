import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Gives a control drawn smaller than a finger the target of one: [child]
/// centred in a box at least [minSize] high and wide, with [gap] at least
/// around it, and every touch in the box taken by the child, as Material
/// pads its own controls (`MaterialTapTargetSize.padded`). A chip drawn 40
/// high keeps its look and answers over 48.
///
/// The box holds the room a row of such controls kept between them: a
/// `Wrap` of chips 8 apart puts them in boxes with a [gap] of 8 and no run
/// spacing of its own, and draws them where they were.
class TouchTarget extends SingleChildRenderObjectWidget {
  const new({required this.minSize, this.gap = Size.zero, super.child, super.key});

  /// The smallest box, width and height.
  final Size minSize;

  /// The room kept beside and above the child, both sides together.
  final Size gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTouchTarget(minSize: minSize, gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderTouchTarget renderObject) {
    renderObject
      ..minSize = minSize
      ..gap = gap;
  }
}

/// The box of [TouchTarget].
class RenderTouchTarget extends RenderShiftedBox {
  new({required this._minSize, required this._gap}) : super(null);

  Size get minSize => _minSize;
  Size _minSize;
  set minSize(Size value) {
    if (_minSize == value) return;
    _minSize = value;
    markNeedsLayout();
  }

  Size get gap => _gap;
  Size _gap;
  set gap(Size value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  Size _boxOf(Size child) => Size(
    math.max(child.width + gap.width, minSize.width),
    math.max(child.height + gap.height, minSize.height),
  );

  BoxConstraints _childConstraints(BoxConstraints constraints) => constraints.loosen().deflate(
    EdgeInsets.symmetric(horizontal: gap.width / 2, vertical: gap.height / 2),
  );

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max((child?.getMinIntrinsicWidth(height) ?? 0) + gap.width, minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max((child?.getMaxIntrinsicWidth(height) ?? 0) + gap.width, minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max((child?.getMinIntrinsicHeight(width) ?? 0) + gap.height, minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max((child?.getMaxIntrinsicHeight(width) ?? 0) + gap.height, minSize.height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(minSize);
    return constraints.constrain(_boxOf(child.getDryLayout(_childConstraints(constraints))));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(minSize);
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(_boxOf(child.size));
    (child.parentData! as BoxParentData).offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || !size.contains(position)) return false;
    // A touch in the box beside the child is a touch of the child, at its
    // centre.
    final centre = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(centre),
      position: centre,
      hitTest: (result, position) => child.hitTest(result, position: centre),
    );
  }
}

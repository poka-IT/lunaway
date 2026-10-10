import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The first of [children] that fits on one line of the width it gets,
/// else the last: the same words in ever shorter forms, longest first
/// ("Délégation à la sécurité routière, liste du 6 oct.", then
/// "Délégation à la sécurité routière…"). A child fits when its widest
/// line, unwrapped, is no wider than the room ([RenderBox.getMaxIntrinsicWidth]).
///
/// Unlike a [LayoutBuilder], it answers its intrinsic sizes: the guidance
/// measures the height of its notices before it places them beside its
/// buttons. Only the child shown is painted, hit and read by a screen
/// reader.
class FirstThatFits extends MultiChildRenderObjectWidget {
  const new({required super.children, super.key});

  @override
  MultiChildRenderObjectElement createElement() => _FirstThatFitsElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFirstThatFits();
}

/// Tells the inspector and the tests' finders of the child shown alone:
/// the others are words no one sees.
class _FirstThatFitsElement extends MultiChildRenderObjectElement {
  new(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final shown = (renderObject as _RenderFirstThatFits)._shown;
    for (final child in children) {
      if (child.renderObject == shown) visitor(child);
    }
  }
}

class _FitsParentData extends ContainerBoxParentData<RenderBox>;

class _RenderFirstThatFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitsParentData> {
  RenderBox? _shown;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitsParentData) child.parentData = _FitsParentData();
  }

  RenderBox? _choose(double width) {
    var child = firstChild;
    while (child != null) {
      final next = childAfter(child);
      if (next == null || child.getMaxIntrinsicWidth(double.infinity) <= width) return child;
      child = next;
    }
    return null;
  }

  @override
  double computeMinIntrinsicWidth(double height) => lastChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) => firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _choose(width)?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _choose(width)?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = _choose(constraints.maxWidth);
    return child == null
        ? constraints.smallest
        : constraints.constrain(child.getDryLayout(constraints));
  }

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) =>
      _choose(constraints.maxWidth)?.getDryBaseline(constraints, baseline);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _shown?.getDistanceToActualBaseline(baseline);

  @override
  void performLayout() {
    final shown = _shown = _choose(constraints.maxWidth);
    // Every child is laid out, so none is left without a size; only the
    // one shown gives its own.
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(constraints, parentUsesSize: child == shown);
    }
    size = shown == null ? constraints.smallest : constraints.constrain(shown.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown case final child?) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown?.hitTest(result, position: position) ?? false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_shown case final child?) visitor(child);
  }
}

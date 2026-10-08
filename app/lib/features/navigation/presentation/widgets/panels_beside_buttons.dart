import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The parts of [PanelsBesideButtons].
enum PanelSlot { banner, notices, buttons }

/// The guidance's panels on a phone held upright: the maneuver [banner] and
/// the [notices] under it from the top, the column of map [buttons] at the
/// bottom right, above the bottom bar. A panel that would reach down to the
/// buttons is laid out narrower, beside them: on a small phone with large
/// text the column rises to the banner, and a notice under it would
/// otherwise lose its right edge under the buttons. A panel that ends above
/// the buttons keeps the whole width.
///
/// Decided within one layout, from the sizes of this frame: a notice that
/// appears is never drawn under the buttons, not even for one frame.
class PanelsBesideButtons extends SlottedMultiChildRenderObjectWidget<PanelSlot, RenderBox> {
  const new({
    required this.padding,
    required this.gap,
    this.banner,
    this.notices,
    this.buttons,
    super.key,
  });

  /// From the edges of the screen: the top and the sides for the panels,
  /// the right and the bottom for the buttons.
  final EdgeInsets padding;

  /// Between a narrowed panel and the buttons.
  final double gap;

  final Widget? banner;
  final Widget? notices;
  final Widget? buttons;

  @override
  Iterable<PanelSlot> get slots => PanelSlot.values;

  @override
  Widget? childForSlot(PanelSlot slot) => switch (slot) {
    PanelSlot.banner => banner,
    PanelSlot.notices => notices,
    PanelSlot.buttons => buttons,
  };

  @override
  RenderPanelsBesideButtons createRenderObject(BuildContext context) =>
      RenderPanelsBesideButtons(padding: padding, gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderPanelsBesideButtons renderObject) =>
      renderObject
        ..padding = padding
        ..gap = gap;
}

/// The layout of [PanelsBesideButtons].
class RenderPanelsBesideButtons extends RenderBox
    with SlottedContainerRenderObjectMixin<PanelSlot, RenderBox> {
  new({required this._padding, required this._gap});

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  /// Painted in this order, so the buttons stay over a panel that grows
  /// while it animates; hit in the reverse order.
  Iterable<RenderBox> get _ordered => [for (final slot in PanelSlot.values) ?childForSlot(slot)];

  static Offset _offsetOf(RenderBox child) => (child.parentData! as BoxParentData).offset;

  static void _place(RenderBox child, Offset at) =>
      (child.parentData! as BoxParentData).offset = at;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final double width = math.max(0, size.width - padding.horizontal);
    var buttonsTop = double.infinity;
    var buttonsWidth = 0.0;
    if (childForSlot(PanelSlot.buttons) case final buttons?) {
      // Unbounded in height, as a child of a Stack placed by its bottom:
      // a column takes the height of its buttons, not the screen's.
      buttons.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      buttonsTop = size.height - padding.bottom - buttons.size.height;
      buttonsWidth = buttons.size.width;
      _place(buttons, Offset(size.width - padding.right - buttonsWidth, buttonsTop));
    }
    var y = padding.top;
    for (final slot in const [PanelSlot.banner, PanelSlot.notices]) {
      final panel = childForSlot(slot);
      if (panel == null) continue;
      panel.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      if (y + panel.size.height > buttonsTop) {
        panel.layout(
          BoxConstraints.tightFor(width: math.max(0, width - buttonsWidth - gap)),
          parentUsesSize: true,
        );
      }
      _place(panel, Offset(padding.left, y));
      y += panel.size.height;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _ordered) {
      context.paintChild(child, offset + _offsetOf(child));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _ordered.toList().reversed) {
      final hit = result.addWithPaintOffset(
        offset: _offsetOf(child),
        position: position,
        hitTest: (result, transformed) => child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

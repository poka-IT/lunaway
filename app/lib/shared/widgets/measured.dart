import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tells [onHeight] the height its child takes, after the frame that laid
/// it out and only when it changed: for a parent that keeps room for a
/// notice whose height depends on its text.
class ReportsHeight extends SingleChildRenderObjectWidget {
  const new({required this.onHeight, required Widget super.child, super.key});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReportsHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderReportsHeight).onHeight = onHeight;
}

class _RenderReportsHeight extends RenderProxyBox {
  new(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(height);
    });
  }
}

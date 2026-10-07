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

/// Tells [onRect] where its child stands in the window, after a frame that
/// laid it out and only when that changed: for the web page's first map,
/// which opens where the app's map will stand.
class ReportsRect extends SingleChildRenderObjectWidget {
  const new({required this.onRect, required Widget super.child, super.key});

  final ValueChanged<Rect> onRect;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReportsRect(onRect);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderReportsRect).onRect = onRect;
}

class _RenderReportsRect extends RenderProxyBox {
  new(this.onRect);

  ValueChanged<Rect> onRect;
  Rect? _reported;

  @override
  void performLayout() {
    super.performLayout();
    // Where the box stands is known once the whole frame is laid out.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached || !hasSize) return;
      final rect = localToGlobal(Offset.zero) & size;
      if (rect == _reported) return;
      _reported = rect;
      onRect(rect);
    });
  }
}

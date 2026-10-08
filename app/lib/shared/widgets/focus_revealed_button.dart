import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lunaway/shared/widgets/floating.dart';

/// A button over the map for the keyboard and the screen readers, as a web
/// page's "skip link": in the focus order and the semantics tree at all
/// times, drawn only while it holds the keyboard focus or a screen reader
/// runs, and out of the way of a finger or a mouse while hidden. What a
/// touch or a click on the map does, without a pointer.
class FocusRevealedButton extends StatefulWidget {
  const new({required this.icon, required this.label, required this.onPressed, super.key});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<FocusRevealedButton> createState() => _FocusRevealedButtonState();
}

class _FocusRevealedButtonState extends State<FocusRevealedButton> {
  final _focus = FocusNode(debugLabel: 'focus revealed button');

  /// Moves the button between its hidden frame and its floating one: the
  /// key keeps its element, so the focus stays on it.
  final GlobalKey _button = GlobalKey();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  void _changed() {
    if (_focus.hasFocus != _focused) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _focused || MediaQuery.accessibleNavigationOf(context);
    final button = KeyedSubtree(
      key: _button,
      child: TextButton.icon(
        focusNode: _focus,
        onPressed: widget.onPressed,
        icon: Icon(widget.icon),
        label: Text(widget.label),
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
    );
    if (shown) return FloatingSurface(child: button);
    // Hidden: no pointer reaches it (the map under it takes the touch), but
    // a screen reader still finds it and the keyboard still tabs to it.
    return _PassThrough(child: Opacity(opacity: 0, alwaysIncludeSemantics: true, child: button));
  }
}

/// Lets every pointer through to what lies under it; its semantics stay.
class _PassThrough extends SingleChildRenderObjectWidget {
  const new({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPassThrough();
}

class _RenderPassThrough extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The look of a [BusyButton], one per Material button of the theme.
enum BusyLook { filled, tonal, outlined, text }

/// How long a wait goes before the button says what is going on.
const Duration slowWait = Duration(seconds: 10);

/// A button whose action waits on something (the network, the storage, a
/// picture being prepared). The tap shows at once: the press, then on the
/// next frame a spinner in place of the icon, or of the label when there is
/// none, at the same size. A second tap meanwhile does nothing. After
/// [slowWait] a line under the label says the wait goes on ([slowText]).
///
/// [busy] is a wait its owner holds (a form being sent); the button's own
/// action counts as well.
class BusyButton extends StatefulWidget {
  const new({
    required this.onPressed,
    required this.label,
    this.icon,
    this.look = BusyLook.filled,
    this.style,
    this.busy = false,
    this.slowText,
    this.slowLine = true,
    super.key,
  });

  /// The action; null disables the button. The button stays busy until the
  /// future completes, failed or not.
  final Future<void> Function()? onPressed;
  final Widget label;
  final Widget? icon;
  final BusyLook look;
  final ButtonStyle? style;
  final bool busy;

  /// What a long wait says; the network's slowness when null.
  final String? slowText;

  /// Says a long wait under the label; off where the line above a form's
  /// button says it.
  final bool slowLine;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _running = false;
  bool _slow = false;
  Timer? _slowTimer;

  bool get _busy => _running || widget.busy;

  @override
  void didUpdateWidget(BusyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy != oldWidget.busy) _watchSlowness();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// Starts the clock of a long wait when one begins, stops it when it ends.
  void _watchSlowness() {
    if (_busy) {
      _slowTimer ??= Timer(slowWait, () {
        if (mounted) setState(() => _slow = true);
      });
    } else {
      _slowTimer?.cancel();
      _slowTimer = null;
      _slow = false;
    }
  }

  Future<void> _press() async {
    final action = widget.onPressed;
    if (_busy || action == null) return;
    setState(() => _running = true);
    _watchSlowness();
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _running = false);
        _watchSlowness();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;
    final onPressed = widget.onPressed == null ? null : _press;
    final spinner = _Spinner(label: context.t.busy.working);
    // The label keeps its room while the spinner stands in for it: the
    // button does not change size under the finger.
    var label = widget.icon == null && busy
        ? Stack(
            alignment: Alignment.center,
            children: [
              Visibility.maintain(visible: false, child: widget.label),
              spinner,
            ],
          )
        : widget.label;
    if (busy && _slow && widget.slowLine) {
      label = Column(
        mainAxisSize: MainAxisSize.min,
        children: [label, _SlowLine(widget.slowText ?? context.t.busy.slow)],
      );
    }
    final icon = widget.icon == null ? null : (busy ? spinner : widget.icon);
    final button = switch (widget.look) {
      BusyLook.filled =>
        icon == null
            ? FilledButton(onPressed: onPressed, style: widget.style, child: label)
            : FilledButton.icon(
                onPressed: onPressed,
                style: widget.style,
                icon: icon,
                label: label,
              ),
      BusyLook.tonal =>
        icon == null
            ? FilledButton.tonal(onPressed: onPressed, style: widget.style, child: label)
            : FilledButton.tonalIcon(
                onPressed: onPressed,
                style: widget.style,
                icon: icon,
                label: label,
              ),
      BusyLook.outlined =>
        icon == null
            ? OutlinedButton(onPressed: onPressed, style: widget.style, child: label)
            : OutlinedButton.icon(
                onPressed: onPressed,
                style: widget.style,
                icon: icon,
                label: label,
              ),
      BusyLook.text =>
        icon == null
            ? TextButton(onPressed: onPressed, style: widget.style, child: label)
            : TextButton.icon(onPressed: onPressed, style: widget.style, icon: icon, label: label),
    };
    return button;
  }
}

/// What a long wait says, small, in the colour of the button's text.
class _SlowLine extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: DefaultTextStyle.of(context).style.color),
    ),
  );
}

/// A small spinner in the colour of the button's text, the size of an icon.
class _Spinner extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? IconTheme.of(context).color;
    final size = IconTheme.of(context).size ?? 18;
    return SizedBox.square(
      dimension: size,
      child: Padding(
        padding: const EdgeInsets.all(Space.hair),
        child: CircularProgressIndicator(strokeWidth: 2.5, color: color, semanticsLabel: label),
      ),
    );
  }
}

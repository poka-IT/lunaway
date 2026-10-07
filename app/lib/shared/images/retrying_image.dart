import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/shared/images/image_fetcher.dart';
import 'package:lunaway/shared/theme/motion.dart';

/// An image of the API that may not be there yet: [placeholder] until its
/// first frame, [waiting] while the proxy has not fetched it from its
/// source, [error] when it failed for good. A photo the proxy asks to wait
/// for is asked again, once the wait is over, as long as it is on screen
/// and the wait is short; a longer one waits for the next time the place
/// opens.
class RetryingImage extends StatefulWidget {
  const new({
    required this.image,
    required this.placeholder,
    required this.waiting,
    required this.error,
    this.fit,
    super.key,
  });

  /// The longest wait the widget sits out on screen.
  static const longestWait = Duration(minutes: 5);

  final ImageProvider image;
  final Widget placeholder;
  final Widget waiting;
  final Widget error;
  final BoxFit? fit;

  @override
  State<RetryingImage> createState() => _RetryingImageState();
}

class _RetryingImageState extends State<RetryingImage> {
  Timer? _retry;

  /// Bumped on each new try, so the image resolves its provider again.
  int _attempt = 0;

  @override
  void didUpdateWidget(RetryingImage old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _retry?.cancel();
      _retry = null;
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry(Duration wait) {
    if (_retry != null || wait > RetryingImage.longestWait) return;
    _retry = Timer(wait, () async {
      // A failed load may stay in the image cache: the next try must not
      // be answered from it.
      await widget.image.evict();
      if (!mounted) return;
      setState(() {
        _retry = null;
        _attempt++;
      });
    });
  }

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey(_attempt),
    image: widget.image,
    fit: widget.fit,
    excludeFromSemantics: true,
    frameBuilder: (context, child, frame, _) => AnimatedSwitcher(
      duration: Motion.of(context, Motion.short),
      child: frame == null ? widget.placeholder : child,
    ),
    errorBuilder: (context, error, _) {
      if (error is PhotoNotYetException) {
        _scheduleRetry(error.retryAfter);
        return widget.waiting;
      }
      return widget.error;
    },
  );
}

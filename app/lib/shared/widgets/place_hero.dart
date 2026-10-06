import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/widgets/place_avatar.dart';

/// A place's mark flying from the list row the user tapped to the header of
/// its details, so the eye follows the place from the list into the sheet.
/// The list and the details live in the same route (a sheet or a pane over
/// the map), where a [Hero] has nothing to fly between; this does the same
/// with an overlay.
abstract final class PlaceHero {
  static _Flight? _pending;

  /// Called by a row as it opens a place: the flight starts from [from], the
  /// mark's rectangle on screen.
  static void launch({
    required String placeId,
    required Rect from,
    required PlaceKind kind,
    OvernightStatus? overnight,
  }) {
    _pending = _Flight(placeId, from, kind, overnight, DateTime.now());
  }

  static _Flight? _take(String placeId) {
    final flight = _pending;
    // A flight waits for its target a short while only: a place opened from
    // the map later must not fly from an old row.
    if (flight == null ||
        flight.placeId != placeId ||
        DateTime.now().difference(flight.at) > const Duration(milliseconds: 800)) {
      return null;
    }
    _pending = null;
    return flight;
  }
}

final class _Flight {
  new(this.placeId, this.from, this.kind, this.overnight, this.at);

  final String placeId;
  final Rect from;
  final PlaceKind kind;
  final OvernightStatus? overnight;
  final DateTime at;
}

/// The mark in a list row, the start of a flight. Use [rectOf] to get its
/// place on screen when the row is tapped.
class PlaceHeroSource extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  static Rect? rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => child;
}

/// The mark in the details header, where a pending flight lands.
class PlaceHeroTarget extends StatefulWidget {
  const new({
    required this.placeId,
    required this.kind,
    required this.size,
    this.overnight,
    super.key,
  });

  final String placeId;
  final PlaceKind kind;
  final OvernightStatus? overnight;
  final double size;

  @override
  State<PlaceHeroTarget> createState() => _PlaceHeroTargetState();
}

class _PlaceHeroTargetState extends State<PlaceHeroTarget> with SingleTickerProviderStateMixin {
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: Motion.emphasized,
  );
  OverlayEntry? _entry;
  var _hidden = false;

  @override
  void initState() {
    super.initState();
    final flight = PlaceHero._take(widget.placeId);
    if (flight != null) {
      _hidden = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fly(flight));
    }
  }

  void _fly(_Flight flight) {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box == null || !box.hasSize || overlay == null || Motion.reduced(context)) {
      setState(() => _hidden = false);
      return;
    }
    final to = box.localToGlobal(Offset.zero) & box.size;
    final tween = MaterialRectArcTween(begin: flight.from, end: to);
    final curve = CurvedAnimation(parent: _flight, curve: Curves.fastOutSlowIn);
    _entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: curve,
        builder: (_, _) {
          final rect = tween.evaluate(curve)!;
          return Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: FittedBox(
                child: PlaceAvatar(
                  kind: flight.kind,
                  overnight: flight.overnight,
                  size: widget.size,
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
    unawaited(
      _flight.forward().whenComplete(() {
        _entry?.remove();
        _entry = null;
        if (mounted) setState(() => _hidden = false);
      }),
    );
  }

  @override
  void dispose() {
    _entry?.remove();
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _hidden ? 0 : 1,
    child: PlaceAvatar(kind: widget.kind, overnight: widget.overnight, size: widget.size),
  );
}

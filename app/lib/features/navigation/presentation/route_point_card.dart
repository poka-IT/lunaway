import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A point of the route map the user tapped or held: a place, a station or
/// a bare point.
@immutable
final class RoutePoint {
  const new({required this.position, this.title, this.subtitle, this.placeId, this.poiId});

  final LatLng position;

  /// The place's or the station's name; a bare point has none.
  final String? title;

  /// A line under it: the kind of place, the price of the fuel.
  final String? subtitle;
  final String? placeId;
  final String? poiId;

  RouteStop get stop => RouteStop(position: position, label: title, placeId: placeId, poiId: poiId);
}

/// What the user chose on the card.
sealed class RoutePointChoice {
  const new();
}

/// Add the point as a stop, on the route [quote] computed.
final class AddStopChoice extends RoutePointChoice {
  const new(this.quote);

  final StopQuote quote;
}

/// Go to the point instead of the destination, without the stops.
final class GoDirectlyChoice extends RoutePointChoice {
  const new();
}

/// Open the place's card.
final class OpenCardChoice extends RoutePointChoice {
  const new();
}

/// The card of [point], with its three actions in reach: add it as a stop
/// (the extra time shown once the detour is computed by [quote]), go there
/// directly, see its card when it is a place. [quote] answers null when no
/// stop can be added (five already, no position yet).
Future<RoutePointChoice?> showRoutePointCard(
  BuildContext context, {
  required RoutePoint point,
  required Future<StopQuote?> Function(RouteStop stop) quote,
  required bool stopsFull,
}) => showModalBottomSheet<RoutePointChoice>(
  context: context,
  showDragHandle: true,
  builder: (context) => RoutePointCard(point: point, quote: quote, stopsFull: stopsFull),
);

/// The body of the card, public for the tests.
class RoutePointCard extends StatefulWidget {
  const new({required this.point, required this.quote, required this.stopsFull, super.key});

  final RoutePoint point;
  final Future<StopQuote?> Function(RouteStop stop) quote;
  final bool stopsFull;

  @override
  State<RoutePointCard> createState() => _RoutePointCardState();
}

class _RoutePointCardState extends State<RoutePointCard> {
  StopQuote? _quote;
  bool _quoting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.stopsFull) unawaited(_ask());
  }

  Future<void> _ask() async {
    setState(() => _quoting = true);
    StopQuote? quote;
    try {
      quote = await widget.quote(widget.point.stop);
    } on Object {
      quote = null;
    }
    if (!mounted) return;
    setState(() {
      _quoting = false;
      _quote = quote;
      _failed = quote == null || quote.extraS == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final point = widget.point;
    final title = point.title ?? t.navigation.stops.point;
    final where =
        '${point.position.lat.toStringAsFixed(5)}, ${point.position.lon.toStringAsFixed(5)}';
    final quote = _quote;
    final canAdd = !widget.stopsFull && !_quoting && !_failed && quote != null;
    final hint = widget.stopsFull
        ? t.navigation.stops.full
        : _failed
        ? t.navigation.stops.noRoute
        : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
            const SizedBox(height: Space.xxs),
            Text(
              point.subtitle ?? where,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.l),
            FilledButton.icon(
              onPressed: canAdd ? () => Navigator.pop(context, AddStopChoice(quote)) : null,
              icon: _quoting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.add),
              label: Text(t.addStop(quote, quoting: _quoting)),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            ),
            if (hint != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Space.s),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, const GoDirectlyChoice()),
              icon: const Icon(AppIcons.directions),
              label: Text(t.navigation.stops.goDirectly),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            ),
            if (point.placeId != null) ...[
              const SizedBox(height: Space.s),
              TextButton(
                onPressed: () => Navigator.pop(context, const OpenCardChoice()),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(t.navigation.stops.openCard),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

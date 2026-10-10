import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/modal_sheet.dart';

final _log = Logger('route_point');

/// A point of the route map the user tapped or held: a place, a station, a
/// stop of the route, or a bare point.
@immutable
final class RoutePoint {
  const new({
    required this.position,
    this.title,
    this.subtitle,
    this.placeId,
    this.poiId,
    this.stopIndex,
    this.credit,
  });

  final LatLng position;

  /// The place's or the station's name; a bare point has none.
  final String? title;

  /// A line under it: the kind of place, the price of the fuel.
  final String? subtitle;
  final String? placeId;
  final String? poiId;

  /// Its place among the route's stops, when it is one already.
  final int? stopIndex;

  /// Where what the card says comes from (a station's price).
  final String? credit;

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

/// Take the stop out of the route.
final class RemoveStopChoice extends RoutePointChoice {
  const new(this.stop);

  final RouteStop stop;
}

/// Go to the point instead of the destination, without the stops.
final class GoDirectlyChoice extends RoutePointChoice {
  const new();
}

/// Open the place's card.
final class OpenCardChoice extends RoutePointChoice {
  const new();
}

/// The card of [point], with its actions in reach: add it as a stop (the
/// extra time shown once the detour is computed by [quote]) or take it out
/// when it is one, go there directly, see its card when it is a place.
/// [quote] answers null when no stop can be added (five already, no
/// position yet), and throws a [RouteFailure] when the route was not
/// computed.
Future<RoutePointChoice?> showRoutePointCard(
  BuildContext context, {
  required RoutePoint point,
  required Future<StopQuote?> Function(RouteStop stop) quote,
  required bool stopsFull,
}) => showSheet<RoutePointChoice>(
  context,
  // A phone on its side in the cab, or large text: the card scrolls
  // rather than hide its last actions.
  isScrollControlled: true,
  builder: (context) => RoutePointCard(point: point, quote: quote, stopsFull: stopsFull),
);

/// The place's own card over the route, in a sheet: the route and the
/// guidance stay where they are.
Future<void> showPlaceCard(BuildContext context, String placeId) => showSheet<void>(
  context,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.94,
    builder: (context, scroll) => PlaceDetails(
      placeId: placeId,
      scrollController: scroll,
      onClose: () => Navigator.pop(context),
      // No action bar over a route: the card copies the coordinates.
      copyCoordinates: true,
    ),
  ),
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

  /// Why no detour is shown: null while it is fine.
  String Function(Translations t)? _problem;

  bool get _isStop => widget.point.stopIndex != null;

  @override
  void initState() {
    super.initState();
    _quoting = !widget.stopsFull && !_isStop;
    if (_quoting) unawaited(_ask());
  }

  Future<void> _ask() async {
    StopQuote? quote;
    String Function(Translations t)? problem;
    try {
      quote = await widget.quote(widget.point.stop);
      if (quote == null) {
        problem = (t) => t.navigation.stops.noQuote;
      } else if (quote.plan.status != RouteStatus.ok) {
        problem = (t) => t.navigation.stops.noRoute;
      } else if (quote.extraS == null) {
        problem = (t) => t.navigation.stops.noQuote;
      }
    } on RouteFailure catch (f) {
      // Offline or refused is no verdict on the vehicle.
      problem = f.kind == RouteFailureKind.offline
          ? (t) => t.navigation.stops.offline
          : (t) => t.navigation.stops.noQuote;
    } on Object catch (e, st) {
      _log.warning('a stop could not be priced', e, st);
      problem = (t) => t.navigation.stops.noQuote;
    }
    if (!mounted) return;
    setState(() {
      _quoting = false;
      _quote = quote;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final point = widget.point;
    final title = point.title ?? t.navigation.stops.point;
    final degrees = NumberFormat('0.00000', t.$meta.locale.languageCode);
    final where = '${degrees.format(point.position.lat)} · ${degrees.format(point.position.lon)}';
    final quote = _quote;
    final canAdd = !widget.stopsFull && !_quoting && _problem == null && quote != null;
    final hint = widget.stopsFull ? t.navigation.stops.full : _problem?.call(t);
    final index = point.stopIndex;
    return SafeArea(
      child: SingleChildScrollView(
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
            if (point.credit case final credit?) ...[
              const SizedBox(height: Space.xxs),
              Text(
                credit,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Space.l),
            if (index != null)
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, RemoveStopChoice(point.stop)),
                icon: const Icon(AppIcons.close),
                label: Text(t.navigation.stops.remove),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              )
            else ...[
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

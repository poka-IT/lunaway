import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/data/poi_repository.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';
import 'package:lunaway/shared/widgets/status_views.dart';
import 'package:lunaway/shared/widgets/whole_words_text.dart';

/// Closer than this, a point is "on site".
const onSiteM = 50.0;

/// "Around this place" on a place's page: for each category, the point the
/// traveller wants (open now first, open around the clock first at night,
/// then the nearest), with its distance and its state. Read online once,
/// then kept: a place opened before reads it again without network, its
/// hours valid for 14 days.
class PlaceSurroundings extends ConsumerWidget {
  const new({required this.place, super.key});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    // The place's clock: its surroundings share it, and a point without an
    // address would otherwise read France's.
    final zone = PlaceZone.of(place.address?.countryCode, place.position);
    final night = isNight(now, zone: zone);
    final body = switch (ref.watch(placeSurroundingsProvider(place.id))) {
      AsyncValue(
        value: Read(value: final groups, :final fetchedAt, :final offline),
        :final hasError,
      ) =>
        () {
          final rows = [
            for (final g in groups)
              if (g.pois.isNotEmpty) sortForReading(g.pois, now, night: night).first,
          ];
          if (rows.isEmpty) return Text(t.poi.aroundEmpty, style: muted);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final poi in rows) _Row(poi: poi, now: now, zone: zone, from: place.id),
              // A copy kept: when the network did not answer, or the server
              // refused to read it again.
              if (offline || hasError)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    offline
                        ? t.poi.readOffline(when: t.agoFine(fetchedAt, now))
                        : t.poi.readStale(when: t.agoFine(fetchedAt, now)),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          );
        }(),
      AsyncError(:final error) => Row(
        children: [
          Expanded(
            child: Text(
              // No network and no copy kept: the network, not the place.
              error is GraphQLNetworkException ? t.poi.aroundOffline : t.poi.aroundError,
              style: muted,
            ),
          ),
          BusyButton(
            onPressed: () async => ref.invalidate(placeSurroundingsProvider(place.id)),
            // Turning while the surroundings are asked again.
            busy: ref.watch(placeSurroundingsProvider(place.id)).isLoading,
            look: BusyLook.text,
            label: Text(t.common.retry),
          ),
        ],
      ),
      _ => const Column(children: [SkeletonTile(), SkeletonTile()]),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(t.poi.around, style: theme.textTheme.titleLarge)),
          const SizedBox(height: Space.m),
          body,
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const new({required this.poi, required this.now, required this.zone, required this.from});

  final Poi poi;
  final DateTime now;
  final PlaceZone zone;
  final String from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final distance = poi.distanceM;
    final closed = poi.hours.opennessAt(now) == PoiOpenness.closed;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          onTap: () {
            ref.read(mapFlowProvider.notifier).select(PoiSelection(poi.feature, from: from));
            unawaited(ref.read(mapControllerProvider)?.moveTo(poi.position));
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              child: Row(
                children: [
                  PoiAvatar(kind: poi.kind, size: 40, faded: closed),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WholeWordsText(
                          t.poiTitle(poi.name, poi.kind),
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Unknown hours say nothing here: a fountain or a
                        // dump station rarely has any.
                        if (poi.hours.opennessAt(now) != PoiOpenness.unknown)
                          Text(
                            t.poiOpening(poi.hours, now, zone: zone),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: poiOpeningColor(scheme, poi.hours, now),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  if (distance != null)
                    Text(
                      distance < onSiteM ? t.poi.onSite : t.distance(distance),
                      style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  Icon(AppIcons.chevron, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/poi/application/poi_providers.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The shops and services matching the map's search, under the places and
/// the towns: asked of the API once typing pauses (the places are searched
/// on the device). Offline, one line says so; nothing found, nothing shows.
class PoiSearchSection extends ConsumerWidget {
  const new({required this.query, required this.onTap, this.near, this.from, super.key});

  final String query;

  /// Where the matches are ranked from: the centre of the map, which the
  /// tiles already ask for, never the user's position.
  final LatLng? near;

  /// The user's position, for the distances, computed here.
  final LatLng? from;
  final ValueChanged<Poi> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (query.trim().length < 3) return const SizedBox.shrink();
    final now = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    Widget header() => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.xxs),
      child: Text(
        t.poi.searchSection,
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    return switch (ref.watch(poiSearchProvider(query, near: near))) {
      AsyncValue(value: final pois?) when pois.isEmpty => const SizedBox.shrink(),
      AsyncValue(value: final pois?) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header(),
          for (final poi in pois)
            ListTile(
              leading: PoiAvatar(kind: poi.kind, size: 40),
              title: Text(t.poiTitle(poi.name, poi.kind), maxLines: 2),
              subtitle: Text(
                [
                  t.poiKind(poi.kind),
                  if (from case final from?) t.distance(poi.position.distanceTo(from)),
                  t.poiOpening(poi.hours, now),
                ].join(' · '),
              ),
              onTap: () => onTap(poi),
            ),
        ],
      ),
      AsyncError() => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
        child: Text(
          t.poi.searchOffline,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      _ => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
        child: Text(
          t.poi.searching,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    };
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/fuel.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The stations along [line] from [fromM], cheapest first with the detour
/// counted; one tap on "Ajouter" makes the station a stop through [onAdd].
Future<void> showFuelSheet(
  BuildContext context, {
  required List<LatLng> line,
  required double fromM,
  required Future<void> Function(FuelOffer offer) onAdd,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FuelSheet(line: line, fromM: fromM, onAdd: onAdd),
);

/// The body of the fuel list, public for the tests.
class FuelSheet extends ConsumerStatefulWidget {
  const new({required this.line, required this.fromM, required this.onAdd, super.key});

  final List<LatLng> line;
  final double fromM;
  final Future<void> Function(FuelOffer offer) onAdd;

  @override
  ConsumerState<FuelSheet> createState() => _FuelSheetState();
}

class _FuelSheetState extends ConsumerState<FuelSheet> {
  /// Another fuel than the vehicle's, chosen here (LPG for the heating).
  VehicleFuel? _fuel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(routeSettingsControllerProvider).value ?? const NavigationSettings();
    final fuel = _fuel ?? settings.fuel;
    // From the last half kilometre: a list asked again while driving reuses
    // the answer of the same stretch.
    final query = FuelQuery(
      line: widget.line,
      fromM: (widget.fromM / 500).floor() * 500,
      fuel: fuel,
    );
    final offers = ref.watch(fuelOffersProvider(query));
    ref.listen(fuelOffersProvider(query), (_, next) {
      if (next.value case final shown?) ref.read(shownFuelOffersProvider.notifier).show(shown);
    });
    final now = ref.watch(clockProvider)();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Padding(
        // Clear of the system's gesture bar.
        padding: EdgeInsets.fromLTRB(
          Space.l,
          0,
          Space.l,
          Space.s + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(t.navigation.fuel.title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Space.s),
            // One row that scrolls: the list keeps its height on a phone
            // turned sideways with large text.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in VehicleFuel.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s),
                      child: ChoiceChip(
                        label: Text(t.fuelName(f)),
                        selected: f == fuel,
                        onSelected: (_) => setState(() => _fuel = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s),
            Expanded(
              child: switch (offers) {
                AsyncData(:final value) when value.isEmpty => Center(
                  child: Text(t.navigation.fuel.empty, textAlign: TextAlign.center),
                ),
                AsyncData(:final value) => ListView.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _OfferTile(
                    offer: value[i],
                    consumption: settings.consumptionL100,
                    units: settings.units,
                    now: now,
                    onAdd: () {
                      Navigator.pop(context);
                      unawaited(widget.onAdd(value[i]));
                    },
                  ),
                ),
                AsyncError() => Center(
                  child: Text(t.navigation.fuel.failed, textAlign: TextAlign.center),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
            const SizedBox(height: Space.s),
            if (offers.value?.any((o) => o.detourEstimated) ?? false)
              Text(
                t.navigation.fuel.estimated,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            Text(
              // The prices from the national feed; the stations, their names
              // and places, from OpenStreetMap.
              '${t.navigation.fuel.attribution}\n${t.navigation.preview.attributionOsm}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const new({
    required this.offer,
    required this.consumption,
    required this.units,
    required this.now,
    required this.onAdd,
  });

  final FuelOffer offer;
  final double consumption;
  final DistanceUnits units;
  final DateTime now;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = switch (offer.open) {
      StationOpen.open => t.navigation.fuel.open,
      StationOpen.closed => t.navigation.fuel.closed,
      StationOpen.unknown => t.navigation.fuel.unknownHours,
    };
    final effective = effectivePrice(offer, consumptionL100: consumption);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: Space.xs),
      title: Text(
        offer.name ?? offer.brand ?? t.navigation.fuel.station,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          '${t.litrePrice(offer.priceEur)} · ${t.priceAge(offer.priceUpdatedAt, now)}',
          '${t.detour(offer.detourM, offer.detourS, units)} · $open',
          if (offer.detourM >= 100) t.litrePriceWithDetour(effective),
        ].join('\n'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: offer.open == StationOpen.closed ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      trailing: FilledButton.tonal(onPressed: onAdd, child: Text(t.navigation.fuel.add)),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'preview_zones.g.dart';

/// The danger zones the route preview draws, and the lists they come from,
/// cited with them.
typedef PreviewZones = ({List<RouteSpan> spans, List<EnforcementSource> sources});

const PreviewZones noPreviewZones = (spans: [], sources: []);

/// The danger zones the preview draws on [route], read from [origin], where
/// the device is: under the strictest rule of the countries around it, at
/// rest (a preview is read before setting off; while a guidance runs, the
/// rule while driving), only zones, only where the zone's own country
/// allows them. None where no country is known at the device, the
/// strictest reading. The route's countries leave the device, as at the
/// start of a guidance; a position never does (docs/speed-cameras.md).
@riverpod
Future<PreviewZones> previewZones(Ref ref, RouteOption route, LatLng origin) async {
  final locatorFuture = ref.watch(countryLocatorProvider.future);
  final driving = ref.watch(guidanceControllerProvider.select((s) => s != null));
  final feed = ref.watch(enforcementFeedProvider);
  final now = ref.watch(clockProvider)();
  final locator = await locatorFuture;
  final here = locator.around(origin).near;
  if (here.isEmpty || route.line.length < 2) return noPreviewZones;
  final countries = countriesAlong(locator, route.line);
  if (countries.isEmpty) return noPreviewZones;
  final data = await feed.refresh(countries, now);
  final rules = data.rules ?? locator.builtIn;
  final onRoute = EnforcementIndex(data.items).onRoute(route.line);
  final spans = zoneSpans(onRoute, here: rules.strictestOf(here), rules: rules, driving: driving);
  if (spans.isEmpty) return noPreviewZones;
  final cited = {
    for (final r in onRoute)
      if (r.item.kind == EnforcementKind.zone && rules.modeOf(r.item.country).showsWhileDriving)
        ...r.item.sourceIds,
  };
  return (
    spans: spans,
    sources: [
      for (final s in data.sources)
        if (cited.contains(s.id)) s,
    ],
  );
}

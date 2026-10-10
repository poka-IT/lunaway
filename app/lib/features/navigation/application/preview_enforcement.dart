import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_spans.dart';
import 'package:lunaway/features/navigation/domain/speed_limits.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'preview_enforcement.g.dart';

/// What the route preview draws of the speed cameras: the stretches its
/// danger zones cover and the lists they come from, its cameras where
/// points may be shown, each with its own lists.
typedef PreviewEnforcement = ({
  List<RouteSpan> spans,
  List<EnforcementSource> zoneSources,
  List<CameraOnRoute> cameras,
});

const PreviewEnforcement noPreviewEnforcement = (spans: [], zoneSources: [], cameras: []);

/// What the preview draws on [route], read from [device], where the device
/// is (never a start chosen elsewhere): under the strictest rule of the
/// countries around it, once the user's choices apply, the same at rest as
/// while driving (Germany's rule shows nothing: a stop at a light counts
/// as driving there). The zones where the zone's own country allows them;
/// the cameras where the rule at the device shows points and the camera's
/// own country does too. Nothing where no country is known at the device,
/// the strictest reading. While a guidance runs, the vehicle's rule, which
/// follows it across a border at once; before its first fix and once
/// arrived, that rule reads off, the strict side. The route's countries
/// leave the device, as at the start of a guidance; a position never does
/// (docs/speed-cameras.md).
@riverpod
Future<PreviewEnforcement> previewEnforcement(Ref ref, RouteOption route, LatLng device) async {
  final locatorFuture = ref.watch(countryLocatorProvider.future);
  final choicesFuture = ref.watch(drivingAidsSettingsControllerProvider.future);
  final driving = ref.watch(guidanceControllerProvider.select((s) => s?.aids.mode));
  final feed = ref.watch(enforcementFeedProvider);
  final now = ref.watch(clockProvider)();
  final locator = await locatorFuture;
  final near = locator.around(device).near;
  if (driving == null && near.isEmpty) return noPreviewEnforcement;
  if (driving != null && !driving.shows) return noPreviewEnforcement;
  if (route.line.length < 2) return noPreviewEnforcement;
  final countries = countriesAlong(locator, route.line);
  if (countries.isEmpty) return noPreviewEnforcement;
  final data = await feed.refresh(countries, now);
  final table = data.rules ?? locator.builtIn;
  final chosen = {for (final c in (await choicesFuture).exactIn) c.toUpperCase()};
  final rules = table.withChoices(chosen);
  final onRoute = withoutBeside(
    EnforcementIndex(data.items).onRoute(route.line),
    (alongM) => knownLimitAt(route.speedLimits, alongM),
  );
  final here = driving ?? rules.strictestOf(near);
  final spans = zoneSpans(onRoute, here: here, rules: rules);
  // At rest, the choice of a country's positions opens its own cameras:
  // the others show as the rule at the device reads without it. While
  // driving, the guidance's rule, as its own map.
  final cameras = camerasOnRoute(
    onRoute,
    here: driving ?? table.strictestOf(near),
    rules: rules,
    chosen: chosen,
    hereChosen: here,
  );
  if (spans.isEmpty && cameras.isEmpty) return noPreviewEnforcement;
  final byId = {for (final s in data.sources) s.id: s};
  List<EnforcementSource> of(EnforcementItem item) => [for (final id in item.sourceIds) ?byId[id]];
  final cited = {
    if (spans.isNotEmpty)
      for (final r in onRoute)
        if (r.item.kind == EnforcementKind.zone && rules.modeOf(r.item.country).shows)
          ...r.item.sourceIds,
  };
  return (
    spans: spans,
    zoneSources: [
      for (final s in data.sources)
        if (cited.contains(s.id)) s,
    ],
    cameras: [for (final c in cameras) CameraOnRoute(onRoute: c, sources: of(c.item))],
  );
}

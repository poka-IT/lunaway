import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../../helpers/navigation.dart';

RouteWarning warning(
  RouteWarningKind kind, {
  RestrictionPlace place = RestrictionPlace.road,
  double? limit,
  double? vehicle,
}) => RouteWarning(
  kind: kind,
  severity: WarningSeverity.warning,
  limit: limit,
  vehicleValue: vehicle,
  distanceFromStartM: 0,
  geometryIndex: 0,
  position: const LatLng(45, 1),
  source: RestrictionSource.osm,
  certainty: RestrictionCertainty.known,
  place: place,
  externalId: 'way/1',
);

void main() {
  late Translations fr;
  late Translations en;

  setUpAll(() async {
    fr = await AppLocale.fr.build();
    en = await AppLocale.en.build();
  });

  group('the title of a restriction says what it is and its figure', () {
    test('clearances by the place they are at', () {
      String title(RestrictionPlace p) =>
          fr.warningTitle(warning(RouteWarningKind.lowClearance, place: p, limit: 3.2));
      expect(title(RestrictionPlace.underpass), 'Pont bas 3,20 m');
      expect(title(RestrictionPlace.tunnel), 'Tunnel 3,20 m');
      expect(title(RestrictionPlace.buildingPassage), 'Porche 3,20 m');
      expect(title(RestrictionPlace.barrier), 'Barre de hauteur 3,20 m');
      expect(title(RestrictionPlace.road), 'Hauteur limitée 3,20 m');
      expect(
        en.warningTitle(
          warning(RouteWarningKind.lowClearance, place: RestrictionPlace.bridge, limit: 3.2),
        ),
        'Bridge 3.20 m',
      );
    });

    test('masses in tonnes, sizes in metres, bans without a figure', () {
      expect(fr.warningTitle(warning(RouteWarningKind.tooHeavy, limit: 3.5)), 'Poids limité 3,5 t');
      expect(
        en.warningTitle(warning(RouteWarningKind.goodsVehicleWeight, limit: 7.5)),
        'Goods vehicle weight limit 7.5 t',
      );
      expect(
        fr.warningTitle(warning(RouteWarningKind.narrow, limit: 2.2)),
        'Passage étroit 2,20 m',
      );
      expect(fr.warningTitle(warning(RouteWarningKind.motorhomeBan)), 'Interdit aux camping-cars');
      expect(
        fr.warningTitle(warning(RouteWarningKind.unknownClearance)),
        'Passage bas, hauteur inconnue',
      );
      expect(
        fr.warningVehicle(warning(RouteWarningKind.tooHeavy, limit: 3.5, vehicle: 4.2)),
        'votre véhicule : 4,2 t',
      );
    });
  });

  group('distances and durations', () {
    test('metric rounds the way the map does, imperial in feet then miles', () {
      expect(fr.routeDistance(348, DistanceUnits.metric), '350 m');
      expect(fr.routeDistance(2440, DistanceUnits.metric), '2,4 km');
      expect(en.routeDistance(2440, DistanceUnits.metric), '2.4 km');
      expect(en.routeDistance(100, DistanceUnits.imperial), '350 ft');
      expect(en.routeDistance(3218.7, DistanceUnits.imperial), '2.0 mi');
    });

    test('durations read in minutes, then hours and minutes', () {
      expect(fr.routeDuration(20), '1 min');
      expect(fr.routeDuration(12 * 60 + 10), '12 min');
      expect(fr.routeDuration(65 * 60), '1 h 05');
      expect(en.routeDuration(65 * 60), '1 h 05 min');
    });

    test('spoken distances round the way a driver counts', () {
      expect(fr.spokenDistance(487, DistanceUnits.metric), '500 mètres');
      expect(fr.spokenDistance(1940, DistanceUnits.metric), '2 kilomètres');
      expect(fr.spokenDistance(1450, DistanceUnits.metric), '1,5 kilomètre');
      expect(en.spokenDistance(1450, DistanceUnits.metric), '1.5 kilometres');
      expect(en.spokenDistance(160, DistanceUnits.metric), '160 metres');
      expect(en.spokenDistance(1609.344 * 2, DistanceUnits.imperial), '2 miles');
    });

    test('a height is spoken as a driver says it', () {
      expect(fr.spokenSize(3.2), '3 mètres 20');
      expect(fr.spokenSize(3.05), '3 mètres 05');
      expect(fr.spokenSize(4), '4 mètres');
      expect(en.spokenSize(3.2), '3.20 metres');
    });
  });

  group('the spoken guidance', () {
    test('a low bridge ahead is announced with its height and distance', () {
      final w = routeFixture('utrillo_van').routes.single.warnings.single;
      expect(
        TranslatedWording(fr, DistanceUnits.metric).warningAhead(w, 1960),
        'Attention, passage bas de 2 mètres 70 dans 2 kilomètres.',
      );
      expect(
        TranslatedWording(en, DistanceUnits.metric).warningAhead(w, 480),
        'Caution, low clearance of 2.70 metres in 500 metres.',
      );
    });

    test('a new route says how much longer it is, in whole minutes', () {
      final words = TranslatedWording(fr, DistanceUnits.metric);
      expect(words.rerouted(null), 'Nouvel itinéraire.');
      expect(words.rerouted(const Duration(seconds: 20)), 'Nouvel itinéraire.');
      expect(words.rerouted(const Duration(minutes: 8)), 'Nouvel itinéraire, 8 minutes de plus.');
      expect(words.rerouted(const Duration(seconds: 70)), 'Nouvel itinéraire, une minute de plus.');
    });

    test('the background notification has its own words', () {
      final notice = TranslatedWording(fr, DistanceUnits.metric).notice;
      expect(notice.title, 'Lunaway vous guide');
      expect(notice.channel, 'Guidage');
    });
  });

  test('the vehicle line names the type and the figures entered', () {
    expect(
      fr.vehicleSummary(motorhome),
      'Intégral · H\u00a03,30\u00a0m · l\u00a02,30\u00a0m · L\u00a07,4\u00a0m · 3,5\u00a0t',
    );
    expect(
      fr.vehicleSummary(motorhome.copyWith(towing: Towing.car)),
      'Intégral · H\u00a03,30\u00a0m · l\u00a02,30\u00a0m · L\u00a07,4\u00a0m · 3,5\u00a0t, avec attelage',
    );
    expect(fr.dimensionList({MissingDimension.weight, MissingDimension.height}), 'hauteur, poids');
  });
}

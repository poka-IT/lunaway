import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// "Partir d'ici" on the cards of the map (the PO's rule of 2026-10-10): a
/// restaurant, a place, a town or an address is seldom where a trip starts,
/// so the action waits in the card's "…" menu, out of its body and out of
/// its row of actions, for the free point "Ici" as for the rest. The
/// preview keeps its own choice of the start.
void main() {
  const address = AddressMatch(
    kind: AddressKind.houseNumber,
    name: '12 Rue de la République',
    postcode: '69002',
    city: 'Lyon',
    context: '69, Rhône, Auvergne-Rhône-Alpes',
    countryCode: 'FR',
    position: LatLng(45.7665, 4.8360),
    sourceId: 'ban',
    attribution: 'Base Adresse Nationale, IGN Géoplateforme',
  );
  const town = AddressMatch(
    kind: AddressKind.town,
    name: 'Annecy',
    postcode: '74000',
    city: 'Annecy',
    context: '74, Haute-Savoie, Auvergne-Rhône-Alpes',
    countryCode: 'FR',
    position: LatLng(45.8992, 6.1294),
    sourceId: 'ban',
    attribution: 'Base Adresse Nationale, IGN Géoplateforme',
  );
  const restaurant = PoiFeature(
    id: '00000000-0000-7000-8000-0000000000r1',
    kind: PoiKind.restaurant,
    position: LatLng(45.8990, 6.1290),
    name: 'Le Bistrot du Lac',
  );
  const here = LatLng(45.7701, 4.8402);

  final cards = <(String, MapSelection, LatLng, Matcher)>[
    ('a place', PlaceSelection(lakeArea.id), lakeArea.position, isNotNull),
    ('a restaurant', const PoiSelection(restaurant), restaurant.position, contains('Bistrot')),
    (
      'an address',
      const PointSelection(LatLng(45.7665, 4.8360), address: address),
      address.position,
      contains('République'),
    ),
    (
      'a town',
      const PointSelection(LatLng(45.8992, 6.1294), address: town),
      town.position,
      contains('Annecy'),
    ),
    ('the free point "Ici"', const PointSelection(here), here, isNull),
  ];

  for (final (layout, size) in [('phone', phone), ('tablet', tablet), ('desktop', desktop)]) {
    for (final (what, selection, position, label) in cards) {
      testWidgets('$layout, $what: "Partir d\'ici" waits in "…", out of the card and its row of '
          'actions', (tester) async {
        final app = await pumpLunaway(tester, size: size);
        app.container(tester).read(mapFlowProvider.notifier).select(selection);
        await settleShort(tester);
        expect(find.text("Partir d'ici"), findsNothing, reason: 'nowhere in sight');
        expect(find.byType(ActionsBar), findsWidgets, reason: 'the row of actions shows');
        await tester.tap(find.byTooltip("Plus d'actions").first);
        await settleShort(tester);
        await tester.tap(find.text("Partir d'ici"));
        await settleShort(tester);
        expect(
          find.text('Départ choisi : ouvrez maintenant la destination et son itinéraire.'),
          findsOneWidget,
        );
        final start = app.container(tester).read(chosenDepartureProvider);
        expect(start?.position, position);
        expect(start?.label, label);
      });
    }
  }

  testWidgets('the entry reads in every language of the app', (tester) async {
    for (final locale in AppLocale.values) {
      final app = await pumpLunaway(tester, locale: locale);
      app.container(tester).read(mapFlowProvider.notifier).select(const PointSelection(here));
      await settleShort(tester);
      final t = locale.translations;
      await tester.tap(find.byTooltip(t.contribute.more).first);
      await settleShort(tester);
      expect(find.text(t.map.startHere), findsOneWidget, reason: locale.languageCode);
      await tester.pumpWidget(const SizedBox());
    }
  });
}

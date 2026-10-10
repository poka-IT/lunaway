import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/data/demo/demo_places.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// A view of the street zoom, where the list reads the map's tiles.
const _view = MapViewport(
  bounds: GeoBounds(south: 45.86, west: 6.06, north: 45.94, east: 6.24),
  center: LatLng(45.9, 6.15),
  zoom: 13.2,
);

/// A place of the tiles [km] north of the view's centre.
PlaceSummary _tile(String id, String name, double km) => PlaceSummary(
  id: id,
  name: name,
  kind: PlaceKind.motorhomeArea,
  lat: 45.9 + km / 111,
  lon: 6.15,
  overnight: OvernightStatus.allowed,
);

final PlaceSummary _near = _tile('near', 'Aire du Port', 0.5);
final PlaceSummary _mid = _tile('mid', 'Aire du Château', 1.5);
final PlaceSummary _far = _tile('far', 'Aire des Vignes', 2.5);

FakeDigestSource _digestSource() => FakeDigestSource(
  [
    // One Lunaway user's 4 beside 246 ratings of 3.2 elsewhere: 3.2
    // together, below the Château's 3.3.
    PlaceDigest(
      placeId: 'near',
      addedAt: DateTime.utc(2026, 10, 5),
      ratings: const [
        SourceRating(sourceId: communityCcBySourceId, average: 4, count: 1),
        SourceRating(sourceId: extcomSourceId, average: 3.2, count: 246),
      ],
    ),
    PlaceDigest(
      placeId: 'mid',
      addedAt: DateTime.utc(2026, 10, 6),
      ratings: const [SourceRating(sourceId: extcomSourceId, average: 3.3, count: 246)],
      excerpt: const LocalizedText(
        lang: 'fr',
        text: "Cadre naturel à moins d'un km du village et des commerces.",
        sourceId: extcomSourceId,
      ),
    ),
    PlaceDigest(
      placeId: 'far',
      addedAt: DateTime.utc(2026, 10, 7),
      ratings: const [SourceRating(sourceId: communityCcBySourceId, average: 4.6, count: 5)],
      excerpt: const LocalizedText(lang: 'de', text: 'Ruhig.', sourceId: extcomSourceId),
    ),
  ],
  {
    for (final p in [_near, _mid, _far]) p.id: p.position,
  },
);

/// The app on a desktop, its map resting on [_view] with [_near], [_mid]
/// and [_far] in its tiles.
Future<TestApp> _streetList(WidgetTester tester, {FakeDigestSource? digests}) async {
  final map = FakeMap()..viewport = _view;
  final app = await pumpLunaway(
    tester,
    size: desktop,
    places: const [],
    online: FakeOnlinePlaces(samplePlaces),
    map: map,
    digests: digests ?? _digestSource(),
  );
  // Before the map's first camera, the list covers France from the API,
  // and asks the digests of that page by its ids.
  app.digests.idRequests.clear();
  app.digests.areaRequests.clear();
  map.lastProps!.onViewportChanged(_view);
  await settleShort(tester);
  map.lastProps!.onPlacesInView!([_far, _near, _mid], _view.bounds);
  await settleShort(tester, const Duration(seconds: 2));
  return app;
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets("a row shows the external source's rating, said external, when Lunaway has none, "
      'and the opening of its description', (tester) async {
    await _streetList(tester);
    final heard = tester.getSemantics(find.text('Aire du Château')).label;
    expect(
      heard,
      contains("D'après Source communautaire externe : Cadre naturel"),
      reason: 'a screen reader hears the source named in full',
    );
    expect(heard, isNot(contains('Externe ·')));
    final mid = find.ancestor(of: find.text('Aire du Château'), matching: find.byType(InkWell));
    expect(find.descendant(of: mid, matching: find.textContaining('3,3')), findsOneWidget);
    expect(
      find.descendant(of: mid, matching: find.textContaining('246 avis externes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mid, matching: find.textContaining('Externe · Cadre naturel')),
      findsOneWidget,
      reason: 'the excerpt says its source, short, before the text',
    );
    final far = find.ancestor(of: find.text('Aire des Vignes'), matching: find.byType(InkWell));
    expect(find.descendant(of: far, matching: find.textContaining('4,6')), findsOneWidget);
    expect(
      find.descendant(of: far, matching: find.textContaining('externe')),
      findsNothing,
      reason: "Lunaway users' rating is not marked",
    );
    expect(find.text('Ruhig.'), findsNothing, reason: 'a text in another language stays out');
  });

  testWidgets("a row shows one Lunaway rating beside the external source's, each with its count", (
    tester,
  ) async {
    await _streetList(tester);
    final near = find.ancestor(of: find.text('Aire du Port'), matching: find.byType(InkWell));
    String? textOf(Finder f) {
      final widget = tester.widget(f);
      return widget is RichText ? widget.text.toPlainText() : null;
    }

    final lines = [
      for (final e in find.descendant(of: near, matching: find.byType(RichText)).evaluate())
        textOf(find.byWidget(e.widget)),
    ].nonNulls.toList();
    expect(
      lines,
      containsAll(['4,0 (1 avis Lunaway)', '3,2 (246 avis externes)']),
      reason: 'a single rating never stands for the place alone',
    );
    final heard = tester.getSemantics(find.text('Aire du Port')).label;
    expect(heard, contains('4,0 sur 5, 1 avis, Lunaway'));
    expect(heard, contains('3,2 sur 5, 246 avis, Source communautaire externe'));
  });

  testWidgets('on a phone with large text the order of the list stays in reach of the count', (
    tester,
  ) async {
    await pumpLunaway(tester, textScale: 1.5);
    expect(tester.takeException(), isNull, reason: 'no overflow in the header');
    final sort = find.widgetWithText(TextButton, 'Distance').hitTestable();
    expect(sort, findsOneWidget);
    await tester.tap(sort);
    await settleShort(tester);
    expect(find.text('Ajoutés récemment'), findsOneWidget);
  });

  testWidgets('a list read from the tiles asks its digests by the area on the grid, never by id', (
    tester,
  ) async {
    final digests = FakeDigestSource();
    await _streetList(tester, digests: digests);
    expect(digests.areaRequests, [placesQueryBox(_view.bounds)]);
    expect(digests.idRequests, isEmpty, reason: 'the ids in view would say more than the tiles');
    expect(digests.languages.toSet(), {'fr'});
  });

  testWidgets('a page of the API asks the digests of its rows by their ids', (tester) async {
    final digests = FakeDigestSource();
    final app = await pumpLunaway(
      tester,
      size: desktop,
      places: const [],
      online: FakeOnlinePlaces(samplePlaces),
      digests: digests,
    );
    await settleShort(tester, const Duration(seconds: 2));
    final page = app.container(tester).read(nearbyPlacesPageProvider).value!;
    expect(digests.idRequests.expand((ids) => ids).toSet(), {for (final p in page.places) p.id});
    expect(digests.areaRequests, isEmpty);
  });

  testWidgets('the order chosen sorts the list and is kept', (tester) async {
    final app = await _streetList(tester);
    expect(_top(tester, 'Aire du Port'), lessThan(_top(tester, 'Aire du Château')));
    expect(_top(tester, 'Aire du Château'), lessThan(_top(tester, 'Aire des Vignes')));

    await tester.tap(find.widgetWithText(TextButton, 'Distance'));
    await settleShort(tester);
    await tester.tap(find.text('Note').last);
    await settleShort(tester, const Duration(seconds: 2));
    expect(app.settings.value.listSort, ListSort.rating, reason: 'the choice is kept');
    expect(_top(tester, 'Aire des Vignes'), lessThan(_top(tester, 'Aire du Château')));
    expect(_top(tester, 'Aire du Château'), lessThan(_top(tester, 'Aire du Port')));

    await tester.tap(find.widgetWithText(TextButton, 'Note'));
    await settleShort(tester);
    await tester.tap(find.text('Ajoutés récemment').last);
    await settleShort(tester, const Duration(seconds: 2));
    expect(_top(tester, 'Aire des Vignes'), lessThan(_top(tester, 'Aire du Château')));
  });

  testWidgets('a list of the API ranks the nearest it read, and says so', (tester) async {
    final many = demoPlaces(count: 260, now: testNow);
    final online = FakeOnlinePlaces(many);
    await pumpLunaway(
      tester,
      size: desktop,
      places: const [],
      online: online,
      settings: const AppSettings(theme: ThemePreference.light, listSort: ListSort.rating),
    );
    await settleShort(tester, const Duration(seconds: 2));
    expect(online.firsts.last, nearbyRankedLimit, reason: 'the nearest 200 at once');
    expect(find.textContaining('Classés parmi les 200 lieux les plus proches'), findsOneWidget);
    expect(
      online.requests.where((r) => r.startsWith('page:') && r != 'page:'),
      isEmpty,
      reason: 'no further page: it would land among the ranked rows',
    );
  });
}

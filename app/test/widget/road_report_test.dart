import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';

import '../helpers/fake_api.dart';
import '../helpers/navigation.dart';
import '../helpers/pump.dart';

const _spot = LatLng(45.7629, 4.831697);

Future<TestApp> _openPoint(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(1280, 2400),
}) async {
  final app = await pumpLunaway(tester, size: size, api: api);
  app.container(tester).read(selectionProvider.notifier).select(const PointSelection(_spot));
  await settleShort(tester);
  return app;
}

Future<void> _reportWorks(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Signaler un problème ici'));
  await tester.pump();
  await tester.tap(find.text('Signaler un problème ici'));
  await settleShort(tester);
  await tester.tap(find.text('Travaux'));
  await settleShort(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
  await settleShort(tester);
}

void main() {
  testWidgets('a point of the map reports works there, without a course', (tester) async {
    final api = FakeApi();
    await _openPoint(tester, api);
    await _reportWorks(tester);
    expect(api.last('ReportRoadEvent')!['input'], {
      'kind': 'WORKS',
      'lat': _spot.lat,
      'lon': _spot.lon,
    });
    expect(api.last('ReportRoadEvent')!['idempotencyKey'], isNotEmpty);
  });

  testWidgets('without network the report waits in the outbox and says so', (tester) async {
    final api = FakeApi()..offline = true;
    final app = await _openPoint(tester, api);
    await _reportWorks(tester);
    final waiting = await app.container(tester).read(outboxStoreProvider).all();
    expect(waiting.map((e) => e.kind), [ContributionKind.reportRoadEvent]);
    expect(find.text("Pas de réseau : envoi dès qu'il revient"), findsOneWidget);
  });

  testWidgets('the same report made twice while it waits is queued once', (tester) async {
    final api = FakeApi()..offline = true;
    final app = await _openPoint(tester, api);
    await _reportWorks(tester);
    await _reportWorks(tester);
    final waiting = await app.container(tester).read(outboxStoreProvider).all();
    expect(waiting, hasLength(1));
  });

  for (final (country, offered) in [('FR', true), ('CZ', false), (null, true)]) {
    testWidgets('a point in ${country ?? 'no known country'} is '
        '${offered ? '' : 'not '}offered a report', (tester) async {
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 2400),
        api: FakeApi(),
        overrides: navigationOverrides(
          routes: FakeRouteService(const [], routingInfo: europeRouting),
          countries: FakeCountries((_) => country),
        ),
      );
      app.container(tester).read(selectionProvider.notifier).select(const PointSelection(_spot));
      await settleShort(tester);
      expect(find.text('Copier les coordonnées'), findsOneWidget, reason: 'the card is open');
      expect(
        find.text('Signaler un problème ici'),
        offered ? findsOneWidget : findsNothing,
        reason: 'reports are accepted in Spain, France, Gibraltar, Monaco and the Netherlands',
      );
    });
  }

  testWidgets('on a small phone the sheet shows its four kinds and its button in reach', (
    tester,
  ) async {
    final api = FakeApi();
    await _openPoint(tester, api, size: const Size(360, 640));
    await tester.scrollUntilVisible(
      find.text('Signaler un problème ici'),
      150,
      scrollable: find
          .descendant(of: find.byType(PointDetails), matching: find.byType(Scrollable))
          .first,
    );
    await settleShort(tester);
    await tester.tap(find.text('Signaler un problème ici'));
    await settleShort(tester);
    for (final kind in ['Route fermée', 'Travaux', 'Passage étroit', 'Hauteur limitée']) {
      expect(find.text(kind).hitTestable(), findsOneWidget, reason: kind);
    }
    await tester.tap(find.text('Passage étroit'));
    await settleShort(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Signaler').hitTestable());
    await settleShort(tester);
    expect((api.last('ReportRoadEvent')!['input']! as Map)['kind'], 'NARROW_PASSAGE');
  });
}

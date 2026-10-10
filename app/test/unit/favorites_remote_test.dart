import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/account/data/account_service.dart';
import 'package:lunaway/features/account/data/device_keys.dart';
import 'package:lunaway/features/account/data/secret_store.dart';
import 'package:lunaway/features/favorites/data/favorites_sync.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

import '../helpers/fake_api.dart';
import '../helpers/samples.dart';

/// The account's favourites through the API (the fake one, held to the
/// schema): the saved points go and come, an API before them is spoken to
/// in the form it knows, and a refusal of points never blocks the lists.
void main() {
  late FakeApi api;
  late GraphQLFavoritesRemote remote;

  final shop = SavedPoint(
    id: savedPoiPointId('00000000-0000-7000-8000-0000000000b1'),
    kind: SavedPointKind.poi,
    name: 'Boulangerie du Lac',
    position: const LatLng(45.1, 6.1),
    note: 'Pain au levain',
    poiId: '00000000-0000-7000-8000-0000000000b1',
    poiKind: PoiKind.bakery,
  );
  final here = SavedPoint(
    id: savedPointIdAt(const LatLng(45, 6)),
    kind: SavedPointKind.point,
    name: 'Point du 10 oct.',
    position: const LatLng(45, 6),
  );

  setUp(() async {
    api = FakeApi();
    final secrets = MemorySecretStore();
    final service = AccountService(
      client: GraphQLClient(
        endpoint: Uri.parse('$testApiBase/graphql'),
        httpClient: api.client(MockClient((_) async => http.Response('', 404))),
        userAgent: 'Lunaway/test (+https://lunaway.net)',
      ),
      keys: SoftwareDeviceKeys(secrets),
      secrets: secrets,
      locale: () => 'fr',
      clock: () => testNow,
    );
    await service.ensureAccount();
    remote = GraphQLFavoritesRemote(service);
  });
  tearDown(() => expect(api.violations, isEmpty));

  test('a shop and a bare point go with their names, notes and point of interest', () async {
    final lists = await remote.import([
      (name: 'Mes favoris', placeIds: const [], points: [shop, here]),
    ]);
    final sent = (api.last('ImportFavorites')!['lists']! as List<Object?>).single! as Map;
    expect(sent['points'], [
      {
        'id': shop.id,
        'kind': 'POI',
        'name': 'Boulangerie du Lac',
        'note': 'Pain au levain',
        'lat': 45.1,
        'lon': 6.1,
        'poiId': shop.poiId,
        'poiKind': 'BAKERY',
      },
      {'id': here.id, 'kind': 'POINT', 'name': 'Point du 10 oct.', 'lat': 45.0, 'lon': 6.0},
    ]);
    expect(lists.single.points, {shop.id: shop, here.id: here}, reason: 'read back as sent');
    expect(await remote.addPoint(lists.single.id, here), isTrue);
  });

  test('the account lists its points; an API before them, its lists without', () async {
    api.favoriteLists.add({
      'id': '00000000-0000-7000-8000-0000000000c1',
      'name': 'Mes favoris',
      'places': <Object?>[],
      'points': [
        {
          'id': here.id,
          'kind': 'POINT',
          'name': 'Chez Paul',
          'note': null,
          'address': null,
          'lat': 45,
          'lon': 6,
          'poiId': null,
          'poiKind': null,
        },
      ],
    });
    expect((await remote.lists()).single.points?[here.id]?.name, 'Chez Paul');

    api.older = true;
    final older = await remote.lists();
    expect(older.single.points, isNull, reason: 'unknown, not empty: nothing was removed');
    expect(api.olderRefusals, contains('MyFavoriteLists'));
  });

  test('an API before the points imports the lists and places alone', () async {
    api.older = true;
    final lists = await remote.import([
      (name: 'Mes favoris', placeIds: [lakeArea.id], points: [here]),
    ]);
    expect(api.olderRefusals, contains('ImportFavorites'));
    final sent = (api.last('ImportFavorites')!['lists']! as List<Object?>).single! as Map;
    expect(sent.containsKey('points'), isFalse);
    expect(lists.single.points, isNull);
  });

  test('points the account refuses leave the lists and places to go without them', () async {
    api.refuseImportedPoints = true;
    final lists = await remote.import([
      (name: 'Mes favoris', placeIds: [lakeArea.id], points: [here]),
    ]);
    expect(api.operations.where((o) => o == 'ImportFavorites'), hasLength(2));
    expect(lists.single.points, isEmpty, reason: 'the points follow one by one');
  });

  test('a point the account refuses is told apart from a failure', () async {
    final list = (await remote.import([
      (name: 'Mes favoris', placeIds: const [], points: const []),
    ])).single;
    api.refusedPoints.add(here.id);
    expect(await remote.addPoint(list.id, here), isFalse);
    api.offline = true;
    await expectLater(remote.addPoint(list.id, shop), throwsA(isA<GraphQLNetworkException>()));
  });

  test("a saved private host comes without its street, whatever the API sends", () {
    final place = GraphQLFavoritesRemote.placeOperation.parse({
      'place': {
        'id': '00000000-0000-7000-8000-0000000000c1',
        'name': null,
        'kind': 'HOMESTAY',
        'lat': 45.2,
        'lon': 6.2,
        'overnight': 'ALLOWED',
        'address': {'street': '12 chemin des Vignes', 'city': 'Talloires'},
        'municipality': null,
      },
    })!;
    expect(place.street, isNull, reason: "a host's address is never shown");
    expect(place.city, 'Talloires');
  });
}

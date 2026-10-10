import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/user_database.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

const _segur = LatLng(48.850699, 2.308628);

SavedPoint _address({String name = '20 Avenue de Ségur', String? note}) => SavedPoint(
  id: savedPointIdAt(_segur),
  kind: SavedPointKind.address,
  name: name,
  position: _segur,
  note: note,
  address: '20 Avenue de Ségur, 75007 Paris',
);

void main() {
  late UserDatabase db;
  late DriftFavoritesRepository repo;
  var now = DateTime.utc(2026, 10, 10, 9);

  setUp(() {
    db = UserDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 10, 9);
    repo = DriftFavoritesRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('a list holds places and points, newest first, and counts both', () async {
    final list = await repo.defaultListId();
    await repo.add(
      list,
      const PlaceSummary(
        id: 'p1',
        kind: PlaceKind.parking,
        lat: 45,
        lon: 6,
        overnight: OvernightStatus.allowed,
      ),
    );
    now = now.add(const Duration(minutes: 1));
    await repo.addPoint(list, _address(note: 'Ministère'));
    final items = await repo.watchFavorites(list).first;
    expect(items.map((e) => e.key), [savedPointIdAt(_segur), 'p1']);
    final point = items.first as FavoritePointEntry;
    expect(
      (point.point.name, point.point.note, point.point.address),
      ('20 Avenue de Ségur', 'Ministère', '20 Avenue de Ségur, 75007 Paris'),
    );
    expect((await repo.watchLists().first).single.count, 2);
    expect(await repo.watchEntries(list).first, hasLength(1), reason: 'the places alone');
  });

  test('a point saved again keeps its place in the list and takes the new content', () async {
    final list = await repo.defaultListId();
    await repo.addPoint(list, _address());
    final first = (await repo.watchPoints(list).first).single.addedAt;
    now = now.add(const Duration(hours: 1));
    await repo.addPoint(list, _address(name: 'Chez le ministre'));
    final again = (await repo.watchPoints(list).first).single;
    expect(again.addedAt, first);
    expect(again.point.name, 'Chez le ministre');
  });

  test('the lists holding a point, and its saved content, are watched by its id', () async {
    final a = await repo.defaultListId();
    final b = await repo.createList('Paris');
    await repo.addPoint(a, _address());
    await repo.addPoint(b, _address());
    expect(await repo.watchListsOf(_address().id).first, {a, b});
    await repo.updatePoint(_address().renamed('Ségur', 'Entrée côté jardin'));
    final saved = await repo.watchPoint(_address().id).first;
    expect((saved?.name, saved?.note), ('Ségur', 'Entrée côté jardin'));
    for (final e in await repo.watchPoints(b).first) {
      expect(e.point.name, 'Ségur', reason: 'every list holds the same name');
    }
  });

  test('a point taken out of every list comes back in each with the undo', () async {
    final a = await repo.defaultListId();
    final b = await repo.createList('Paris');
    await repo.addPoint(a, _address());
    await repo.addPoint(b, _address());
    final removed = await repo.removePointEverywhere(_address().id);
    expect(removed, hasLength(2));
    expect(await repo.watchPoint(_address().id).first, isNull);
    await repo.restorePoints(removed);
    expect(await repo.watchListsOf(_address().id).first, {a, b});
  });

  test('the undo does not bring back a list deleted meanwhile', () async {
    final b = await repo.createList('Paris');
    await repo.addPoint(b, _address());
    final removed = await repo.removePointEverywhere(_address().id);
    await repo.deleteList(b);
    await repo.restorePoints(removed);
    expect(await repo.watchPoint(_address().id).first, isNull);
  });

  test("a deleted list takes its points with it; a shop keeps its point's kind", () async {
    final b = await repo.createList('Courses');
    const bakery = SavedPoint(
      id: 'shop',
      kind: SavedPointKind.poi,
      name: 'Boulangerie du Lac',
      position: LatLng(45.1, 6.1),
      poiId: 'poi-1',
      poiKind: PoiKind.bakery,
    );
    await repo.addPoint(b, bakery);
    expect((await repo.watchPoint('shop').first)?.poiKind, PoiKind.bakery);
    await repo.deleteList(b);
    expect(await db.select(db.favoritePoints).get(), isEmpty);
  });
}

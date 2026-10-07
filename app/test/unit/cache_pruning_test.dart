import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/database/cache_database.dart';
import 'package:lunaway/core/database/cache_pruning.dart';
import 'package:lunaway/shared/images/image_file_cache.dart';

import '../helpers/pump.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);

  test('copies of pages not read again for 90 days go, the recent ones stay', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = CacheDatabase(memoryDatabase());
    addTearDown(db.close);
    int at(int days) => now.subtract(Duration(days: days)).millisecondsSinceEpoch;
    await db
        .into(db.placeExtrasCache)
        .insert(PlaceExtrasCacheCompanion.insert(placeId: 'old', json: '{}', fetchedAt: at(91)));
    await db
        .into(db.placeExtrasCache)
        .insert(PlaceExtrasCacheCompanion.insert(placeId: 'recent', json: '{}', fetchedAt: at(89)));
    await db
        .into(db.poiCache)
        .insert(PoiCacheCompanion.insert(cacheKey: 'old', json: '{}', fetchedAt: at(120)));
    await db
        .into(db.poiCache)
        .insert(PoiCacheCompanion.insert(cacheKey: 'recent', json: '{}', fetchedAt: at(1)));
    await db
        .into(db.placeCache)
        .insert(PlaceCacheCompanion.insert(placeId: 'old', json: '{}', fetchedAt: at(95)));
    await db
        .into(db.placeCache)
        .insert(PlaceCacheCompanion.insert(placeId: 'recent', json: '{}', fetchedAt: at(2)));
    expect(await pruneOpenedPages(db, now), 3);
    expect((await db.select(db.placeExtrasCache).get()).map((r) => r.placeId), ['recent']);
    expect((await db.select(db.poiCache).get()).map((r) => r.cacheKey), ['recent']);
    expect((await db.select(db.placeCache).get()).map((r) => r.placeId), ['recent']);
  });

  test('photos not shown for 90 days go, the recent ones stay', () async {
    final dir = await Directory.systemTemp.createTemp('images-test');
    addTearDown(() => dir.delete(recursive: true));
    final old = File('${dir.path}/old')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(days: 91)));
    final recent = File('${dir.path}/recent')
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(days: 10)));
    expect(await pruneCachedImages(now, dir: dir), 1);
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });
}

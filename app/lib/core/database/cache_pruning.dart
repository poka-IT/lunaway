import 'package:drift/drift.dart';
import 'package:lunaway/core/database/cache_database.dart';

/// How long the copy of a page the user opened stays on the device. Each
/// copy is a trace of where the user looked; past this it goes. A page
/// opened again with network is read anew within hours, so its copy is
/// that recent.
const openedPagesKeep = Duration(days: 90);

/// Drops the copies of places opened online, of their photos and reviews,
/// and of shops' and services' pages that no opening has read again for
/// [openedPagesKeep]. Returns how many went.
Future<int> pruneOpenedPages(CacheDatabase db, DateTime now) async {
  final cutoff = now.subtract(openedPagesKeep).millisecondsSinceEpoch;
  final extras = await (db.delete(
    db.placeExtrasCache,
  )..where((e) => e.fetchedAt.isSmallerThanValue(cutoff))).go();
  final pois = await (db.delete(
    db.poiCache,
  )..where((e) => e.fetchedAt.isSmallerThanValue(cutoff))).go();
  final places = await (db.delete(
    db.placeCache,
  )..where((e) => e.fetchedAt.isSmallerThanValue(cutoff))).go();
  return extras + pois + places;
}

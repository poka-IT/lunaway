import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/data/place_extras_repository.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';

/// An in-memory [PlacesRepository] with the same filter semantics as the
/// drift one (the drift one is tested against the same expectations).
final class FakePlacesRepository implements PlacesRepository {
  new(List<Place> places, {this.lastSync}) {
    for (final p in places) {
      _places[p.id] = p;
    }
  }

  final Map<String, Place> _places = {};
  final StreamController<void> _changes = StreamController.broadcast();
  DateTime? lastSync;

  /// Makes every read fail, for the error states.
  Exception? failWith;

  List<Place> get all => _places.values.toList();

  void put(Place place) {
    _places[place.id] = place;
    _changes.add(null);
  }

  void remove(String id) {
    _places.remove(id);
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    final error = failWith;
    if (error != null) throw error;
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  bool _keeps(Place p, PlaceFilter f) => f.matches(p.summary, maxHeightM: p.maxHeightM);

  @override
  Stream<List<PlaceSummary>> watchAll(PlaceFilter filter) => _watch(
    () => [
      for (final p in _places.values)
        if (_keeps(p, filter)) p.summary,
    ],
  );

  @override
  Stream<List<PlaceSummary>> watchInBounds(
    GeoBounds bounds,
    PlaceFilter filter, {
    required LatLng center,
    int limit = 200,
  }) => _watch(() {
    final inside = [
      for (final p in _places.values)
        if (bounds.contains(p.position) && _keeps(p, filter)) p.summary,
    ]..sort((a, b) => a.position.distanceTo(center).compareTo(b.position.distanceTo(center)));
    return inside.take(limit).toList();
  });

  @override
  Stream<Place?> watchPlace(String id) => _watch(() => _places[id]);

  @override
  Future<SearchResults> search(String text, {LatLng? near, int limit = 20}) async {
    final q = text.toLowerCase().trim();
    if (q.isEmpty) return SearchResults.empty;
    final places = [
      for (final p in _places.values)
        if ((p.name ?? '').toLowerCase().contains(q)) p.summary,
    ];
    final towns = <String, List<Place>>{};
    for (final p in _places.values) {
      final city = p.address?.city;
      if (city != null && city.toLowerCase().startsWith(q)) {
        towns.putIfAbsent(city, () => []).add(p);
      }
    }
    return SearchResults(
      places: places.take(limit).toList(),
      municipalities: [
        for (final e in towns.entries)
          Municipality(name: e.key, center: e.value.first.position, placeCount: e.value.length),
      ],
    );
  }

  @override
  Stream<int> watchCount() => _watch(() => _places.length);

  @override
  Future<int> countMatching(PlaceFilter filter) async =>
      _places.values.where((p) => _keeps(p, filter)).length;

  @override
  Stream<DateTime?> watchLastSync(String region) => _watch(() => lastSync);

  @override
  Future<int> storageSizeBytes() async => 3 * 1024 * 1024 + 300 * 1024;
}

final class FakeFavoritesRepository implements FavoritesRepository {
  final List<({int id, String? name, bool isDefault})> _lists = [
    (id: 1, name: null, isDefault: true),
  ];
  final List<FavoriteEntry> _entries = [];
  final StreamController<void> _changes = StreamController.broadcast();
  int _nextId = 2;

  List<FavoriteEntry> get entries => List.unmodifiable(_entries);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void _changed() => _changes.add(null);

  @override
  Stream<List<FavoriteList>> watchLists() => _watch(
    () => [
      for (final l in _lists)
        FavoriteList(
          id: l.id,
          name: l.name,
          isDefault: l.isDefault,
          count: _entries.where((e) => e.listId == l.id).length,
        ),
    ],
  );

  @override
  Stream<List<FavoriteEntry>> watchEntries(int listId) =>
      _watch(() => _entries.where((e) => e.listId == listId).toList().reversed.toList());

  @override
  Stream<Set<int>> watchListsOf(String placeId) => _watch(
    () => {
      for (final e in _entries)
        if (e.placeId == placeId) e.listId,
    },
  );

  @override
  Future<void> addToDefault(PlaceSummary place) => add(1, place);

  @override
  Future<void> add(int listId, PlaceSummary place) async {
    _entries
      ..removeWhere((e) => e.listId == listId && e.placeId == place.id)
      ..add(
        FavoriteEntry(
          listId: listId,
          placeId: place.id,
          name: place.name,
          kind: place.kind,
          position: place.position,
          addedAt: DateTime.utc(2026, 10, 6),
        ),
      );
    _changed();
  }

  @override
  Future<void> remove(int listId, String placeId) async {
    _entries.removeWhere((e) => e.listId == listId && e.placeId == placeId);
    _changed();
  }

  @override
  Future<void> removeEverywhere(String placeId) async {
    _entries.removeWhere((e) => e.placeId == placeId);
    _changed();
  }

  @override
  Future<int> createList(String name) async {
    final id = _nextId++;
    _lists.add((id: id, name: name, isDefault: false));
    _changed();
    return id;
  }

  @override
  Future<void> renameList(int listId, String name) async {
    final i = _lists.indexWhere((l) => l.id == listId);
    _lists[i] = (id: listId, name: name, isDefault: _lists[i].isDefault);
    _changed();
  }

  @override
  Future<void> deleteList(int listId) async {
    _lists.removeWhere((l) => l.id == listId && !l.isDefault);
    _entries.removeWhere((e) => e.listId == listId);
    _changed();
  }

  @override
  Future<void> restore(FavoriteEntry entry) async {
    _entries.add(entry);
    _changed();
  }
}

/// Records what the app hands to other apps.
final class FakeExternalActions implements ExternalActions {
  final List<Uri> opened = [];
  final List<String> shared = [];
  bool openSucceeds = true;

  @override
  Future<bool> openUrl(Uri url) async {
    opened.add(url);
    return openSucceeds;
  }

  @override
  Future<void> share(String text, {String? subject, Rect? origin}) async => shared.add(text);
}

/// Photos and reviews served from memory; [online] false makes the network
/// fail.
final class FakeExtrasSource implements PlaceExtrasSource {
  new({this.photos = const [], this.reviews = const [], this.pageSize = 2});

  final List<Photo> photos;
  final List<Review> reviews;
  final int pageSize;
  bool online = true;
  int fetches = 0;

  ReviewPage _page(int start, int first) {
    final end = (start + first).clamp(0, reviews.length);
    return ReviewPage(
      nodes: reviews.sublist(start, end),
      endCursor: '$end',
      hasNextPage: end < reviews.length,
      totalCount: reviews.length,
    );
  }

  @override
  Future<({List<Photo> photos, ReviewPage reviews})?> fetch(
    String placeId, {
    required int first,
  }) async {
    fetches++;
    if (!online) throw StateError('offline');
    return (photos: photos, reviews: _page(0, pageSize));
  }

  @override
  Future<ReviewPage> moreReviews(
    String placeId, {
    required String after,
    required int first,
  }) async {
    if (!online) throw StateError('offline');
    return _page(int.parse(after), pageSize);
  }
}

/// Stands in for the map in widget tests, where platform views do not
/// render: every pin is a button keyed `pin-<id>`, a long press on the map
/// surface reports [longPressAt], and camera commands are recorded.
base class FakeMap implements LunaMapController {
  final List<({LatLng center, double? zoom})> moves = [];
  final List<GeoBounds> fits = [];
  LatLng? userPosition;
  LunaMapProps? lastProps;
  LatLng longPressAt = const LatLng(45.7629, 4.831697);
  MapViewport viewport = const MapViewport(
    bounds: GeoBounds(south: 41, west: -5.5, north: 51.5, east: 10),
    center: LatLng(46.6, 2.5),
    zoom: 6,
  );

  @override
  Future<void> moveTo(LatLng center, {double? zoom}) async =>
      moves.add((center: center, zoom: zoom));

  @override
  Future<void> fitBounds(GeoBounds bounds) async => fits.add(bounds);

  @override
  Future<LatLng?> locateUser() async => userPosition;

  Widget build(BuildContext context, LunaMapProps props) {
    lastProps = props;
    return _FakeMapView(map: this, props: props);
  }
}

class _FakeMapView extends StatefulWidget {
  const new({required this.map, required this.props});

  final FakeMap map;
  final LunaMapProps props;

  @override
  State<_FakeMapView> createState() => _FakeMapViewState();
}

class _FakeMapViewState extends State<_FakeMapView> {
  @override
  void initState() {
    super.initState();
    // Like the real map: ready once built, then the camera rests.
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.props.onMapReady(widget.map);
      widget.props.onViewportChanged(widget.map.viewport);
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('fake-map'),
    onLongPress: () => widget.props.onLongPress(widget.map.longPressAt),
    child: ColoredBox(
      color: const Color(0xFFDDE3EA),
      child: Align(
        child: Wrap(
          children: [
            for (final p in widget.props.places.take(30))
              SizedBox(
                width: 10,
                height: 10,
                child: GestureDetector(
                  key: ValueKey('pin-${p.id}'),
                  onTap: () => widget.props.onPlaceTap(p.id),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

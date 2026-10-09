import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

final _log = Logger('place_thumbs');

/// What a rich mark of the route maps shows of a place it asked the API
/// about: its photos the map may show, and the price of a night when the
/// place has one.
@immutable
final class PlaceThumb {
  const new({this.community = const [], this.external, this.priceEur});

  /// Lunaway's community's photos, newest first, each with its author's
  /// account (null once deleted): a muted author's is never shown.
  final List<({String? authorId, String url})> community;

  /// The external community source's photo of the place ([externalMapPhoto]).
  final String? external;
  final double? priceEur;

  /// The photo the map shows: the newest of the community's by an author
  /// not in [muted], else the external one; null for none.
  String? photo({Set<String> muted = const {}}) {
    for (final p in community) {
      if (p.authorId == null || !muted.contains(p.authorId)) return p.url;
    }
    return external;
  }

  static const _photos = ListEquality<({String? authorId, String url})>();

  @override
  bool operator ==(Object other) =>
      other is PlaceThumb &&
      _photos.equals(other.community, community) &&
      other.external == external &&
      other.priceEur == priceEur;

  @override
  int get hashCode => Object.hash(_photos.hash(community), external, priceEur);
}

/// The sources whose photos a map may show without a credit beside each:
/// Lunaway's community (CC BY 4.0, whose author the place's card names, a
/// tap away) and the external community source, whose mention the map's
/// own credit carries (the places' tiles name it). The open sources'
/// photos stay on the card, beside their credit: DATAtourisme asks for the
/// photo's credit "à proximité immédiate du visuel", Wikimedia Commons and
/// Panoramax for their author and licence (docs/data-sources.md).
const String communityPhotoSource = 'community-cc-by';
const String externalPhotoSource = 'extcom';

/// The external photo a map shows of a place: the external community
/// source's, the place itself before a street view, never the
/// surroundings; null for none.
String? externalMapPhoto(List<({String sourceId, String kind, String thumbUrl})> photos) {
  for (final kind in const ['PLACE', 'STREET_VIEW']) {
    for (final p in photos) {
      if (p.kind == kind && p.sourceId == externalPhotoSource) return p.thumbUrl;
    }
  }
  return null;
}

/// Asks the API about a few places at once.
abstract interface class PlaceThumbsSource {
  /// The places of [ids], [thumbsBatch] at most; a place that is gone has no
  /// entry.
  Future<Map<String, PlaceThumb>> fetch(List<String> ids);
}

/// The most places one request names.
const int thumbsBatch = 8;

/// The requests' sizes: one fixed document each, so the server's persisted
/// queries know them after the first time, and a request costs what it
/// asks. Each place costs the API twice its fixed cost of a database field
/// (`place` and `externalPhotos`, 5 000 each in `schema.rs`): eight are
/// 80 000 of a 90 000 budget, two seconds of a client's refill, where one
/// is the cost of opening a place's card.
const List<int> thumbsSizes = [1, 2, 4, thumbsBatch];

final class GraphQLPlaceThumbs implements PlaceThumbsSource {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<Map<String, PlaceThumb>> fetch(List<String> ids) async {
    if (ids.isEmpty) return const {};
    // The smallest document that holds them; a shorter list repeats its
    // first id, which the server answers once more for nothing.
    final size = thumbsSizes.firstWhere((s) => s >= ids.length, orElse: () => thumbsBatch);
    final padded = [for (var i = 0; i < size; i++) ids[i < ids.length ? i : 0]];
    return await client.execute(placeThumbsOperation(size), {
      for (final (i, id) in padded.indexed) 'p$i': id,
    });
  }
}

final Map<int, GraphQLOperation<Map<String, PlaceThumb>>> _operations = {
  for (final size in thumbsSizes) size: _operation(size),
};

/// The photos and the price of [size] places ([thumbsSizes]), by aliases of
/// `place(id)`.
GraphQLOperation<Map<String, PlaceThumb>> placeThumbsOperation(int size) => _operations[size]!;

GraphQLOperation<Map<String, PlaceThumb>> _operation(int size) => GraphQLOperation(
  name: 'PlaceThumbs$size',
  document:
      '''
query PlaceThumbs$size(${[for (var i = 0; i < size; i++) '\$p$i: UUID!'].join(', ')}) {
${[for (var i = 0; i < size; i++) '  t$i: place(id: \$p$i) { ...ThumbFields }'].join('\n')}
}
fragment ThumbFields on Place {
  id
  priceParkingEur
  coverPhotos { sourceId thumbUrl authorId }
  externalPhotos { sourceId kind thumbUrl }
}''',
  parse: (data) => {
    for (final value in data.values)
      if (value case final Map<Object?, Object?> place)
        if (place['id'] case final String id) id: _thumbOf(place),
  },
);

PlaceThumb _thumbOf(Map<Object?, Object?> place) {
  List<Map<Object?, Object?>> list(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) e,
  ];
  final price = place['priceParkingEur'];
  return PlaceThumb(
    community: [
      for (final p in list(place['coverPhotos']))
        if ((p['sourceId'], p['thumbUrl']) case (communityPhotoSource, final String url))
          (authorId: p['authorId'] as String?, url: url),
    ],
    external: externalMapPhoto([
      for (final p in list(place['externalPhotos']))
        if ((p['sourceId'], p['kind'], p['thumbUrl']) case (
          final String s,
          final String k,
          final String u,
        ))
          (sourceId: s, kind: k, thumbUrl: u),
    ]),
    priceEur: price is num ? price.toDouble() : null,
  );
}

/// The places' thumbs asked during the run, each once: what a rich mark
/// draws comes from here. Asks gathered within [gather] go in one request
/// per [thumbsBatch]; a failed request answers null for its places, which
/// are asked again after [retryAfter] (offline, the marks keep their
/// pictogram meanwhile).
final class PlaceThumbs {
  new(
    this.source, {
    this.gather = const Duration(milliseconds: 60),
    this.retryAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlaceThumbsSource source;
  final Duration gather;
  final Duration retryAfter;
  final DateTime Function() _clock;

  /// Answers known, a place that has no photo included.
  final _known = <String, PlaceThumb>{};

  /// When a place whose request failed may be asked again.
  final _failed = <String, DateTime>{};

  /// Asked, not sent yet.
  final _waiting = <String, Completer<PlaceThumb?>>{};

  /// Sent, not answered yet: asked again meanwhile, they wait for the same
  /// answer instead of going in another request.
  final _inFlight = <String, Completer<PlaceThumb?>>{};
  Timer? _timer;

  /// Places remembered at most; the oldest go first.
  static const _maxKnown = 2000;

  /// What is known of [id] already, without asking.
  PlaceThumb? known(String id) => _known[id];

  /// Whether the last request about [id] failed, not long ago: its mark
  /// keeps its pictogram until it may be asked again.
  bool failed(String id) => _failed[id]?.isAfter(_clock()) ?? false;

  /// The thumb of [id]: known, or asked with the others asked meanwhile.
  /// Null when the request failed, or the place is gone.
  Future<PlaceThumb?> of(String id) {
    if (_known[id] case final thumb?) return Future.value(thumb);
    if (failed(id)) return Future.value();
    final pending = _waiting[id] ?? _inFlight[id];
    if (pending != null) return pending.future;
    final completer = _waiting[id] = Completer<PlaceThumb?>();
    _timer ??= Timer(gather, _send);
    return completer.future;
  }

  void _send() {
    _timer = null;
    final ids = _waiting.keys.toList();
    _inFlight.addAll(_waiting);
    _waiting.clear();
    for (var i = 0; i < ids.length; i += thumbsBatch) {
      unawaited(_ask(ids.sublist(i, i + thumbsBatch > ids.length ? ids.length : i + thumbsBatch)));
    }
  }

  Future<void> _ask(List<String> ids) async {
    Map<String, PlaceThumb>? found;
    try {
      found = await source.fetch(ids);
    } on Object catch (e) {
      _log.fine('could not ask the photos of ${ids.length} places: $e');
    }
    for (final id in ids) {
      final completer = _inFlight.remove(id);
      final thumb = found?[id];
      if (found == null) {
        _failed[id] = _clock().add(retryAfter);
      } else {
        _failed.remove(id);
        _remember(id, thumb ?? const PlaceThumb());
      }
      completer?.complete(thumb);
    }
  }

  void _remember(String id, PlaceThumb thumb) {
    if (_known.length >= _maxKnown) _known.remove(_known.keys.first);
    _known[id] = thumb;
  }

  void dispose() => _timer?.cancel();
}

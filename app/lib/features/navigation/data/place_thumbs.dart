import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:meta/meta.dart';

final _log = Logger('place_thumbs');

/// What a rich mark of the route maps shows of a place it asked the API
/// about: one photo, and the price of a night when the place has one.
@immutable
final class PlaceThumb {
  const new({this.url, this.priceEur});

  /// The photo's 512-pixel thumbnail on the API; null without a photo the
  /// map may show.
  final String? url;
  final double? priceEur;

  @override
  bool operator ==(Object other) =>
      other is PlaceThumb && other.url == url && other.priceEur == priceEur;

  @override
  int get hashCode => Object.hash(url, priceEur);
}

/// The sources whose photos a map may show without a credit beside each:
/// Lunaway's community (CC BY 4.0, whose author the place's card names, a
/// tap away) and the external community source, whose mention the map's
/// own credit carries (the places' tiles name it). The open sources'
/// photos stay on the card, beside their credit: DATAtourisme asks for the
/// photo's credit "à proximité immédiate du visuel", Wikimedia Commons and
/// Panoramax for their author and licence (docs/data-sources.md).
const Set<String> mapPhotoSources = {'community-cc-by', 'extcom'};

/// The photo a map shows of a place, from its community photos (newest
/// first) and its external ones (the place itself first): the first one
/// whose source [mapPhotoSources] allows, the place itself before a street
/// view, never the surroundings.
String? mapPhotoOf({
  required List<({String sourceId, String thumbUrl})> community,
  required List<({String sourceId, String kind, String thumbUrl})> external,
}) {
  for (final p in community) {
    if (mapPhotoSources.contains(p.sourceId)) return p.thumbUrl;
  }
  for (final kind in const ['PLACE', 'STREET_VIEW']) {
    for (final p in external) {
      if (p.kind == kind && mapPhotoSources.contains(p.sourceId)) return p.thumbUrl;
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

/// One request names this many places, always as many: a fixed document, so
/// the server's persisted queries know it after the first time. A shorter
/// list repeats its first id.
const int thumbsBatch = 8;

final class GraphQLPlaceThumbs implements PlaceThumbsSource {
  new(this.client);

  final GraphQLClient client;

  @override
  Future<Map<String, PlaceThumb>> fetch(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final padded = [for (var i = 0; i < thumbsBatch; i++) ids[i < ids.length ? i : 0]];
    return await client.execute(placeThumbsOperation, {
      for (final (i, id) in padded.indexed) 'p$i': id,
    });
  }
}

/// The photo and the price of [thumbsBatch] places, by aliases of
/// `place(id)`.
final placeThumbsOperation = GraphQLOperation<Map<String, PlaceThumb>>(
  name: 'PlaceThumbs',
  document:
      '''
query PlaceThumbs(${[for (var i = 0; i < thumbsBatch; i++) '\$p$i: UUID!'].join(', ')}) {
${[for (var i = 0; i < thumbsBatch; i++) '  t$i: place(id: \$p$i) { ...ThumbFields }'].join('\n')}
}
fragment ThumbFields on Place {
  id
  priceParkingEur
  coverPhotos { sourceId thumbUrl }
  externalPhotos { sourceId kind thumbUrl }
}''',
  parse: (data) => {
    for (final value in data.values)
      if (value case {'id': final String id}) id: _thumbOf(value),
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
    url: mapPhotoOf(
      community: [
        for (final p in list(place['coverPhotos']))
          if ((p['sourceId'], p['thumbUrl']) case (final String s, final String u))
            (sourceId: s, thumbUrl: u),
      ],
      external: [
        for (final p in list(place['externalPhotos']))
          if ((p['sourceId'], p['kind'], p['thumbUrl']) case (
            final String s,
            final String k,
            final String u,
          ))
            (sourceId: s, kind: k, thumbUrl: u),
      ],
    ),
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
  final _waiting = <String, Completer<PlaceThumb?>>{};
  Timer? _timer;

  /// Places remembered at most; the oldest go first.
  static const _maxKnown = 2000;

  /// What is known of [id] already, without asking.
  PlaceThumb? known(String id) => _known[id];

  /// The thumb of [id]: known, or asked with the others asked meanwhile.
  /// Null when the request failed, or the place is gone.
  Future<PlaceThumb?> of(String id) {
    if (_known[id] case final thumb?) return Future.value(thumb);
    if (_failed[id] case final until? when _clock().isBefore(until)) return Future.value();
    final waiting = _waiting[id];
    if (waiting != null) return waiting.future;
    final completer = _waiting[id] = Completer<PlaceThumb?>();
    _timer ??= Timer(gather, _send);
    return completer.future;
  }

  void _send() {
    _timer = null;
    final ids = _waiting.keys.toList();
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
      final completer = _waiting.remove(id);
      final thumb = found?[id];
      if (found == null) {
        _failed[id] = _clock().add(retryAfter);
      } else {
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

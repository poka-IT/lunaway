import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/graphql_client.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/place_digest_source.dart';
import 'package:lunaway/features/places/domain/place_digest.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'place_digests.g.dart';

final _log = Logger('digests');

// keepAlive: a stateless reader over the app-wide client.
@Riverpod(keepAlive: true)
PlaceDigestSource placeDigestSource(Ref ref) =>
    GraphQLPlaceDigestSource(ref.watch(graphQLClientProvider));

/// Most digests kept: about ten screens of a dense area. Past it the
/// oldest go, and a list that shows them again reads them again.
const maxKeptDigests = 3000;

/// The digests the lists read during this run, by place id, in the
/// interface's language: held in memory only, so the external source's
/// ratings never reach the device's stores. An area or a place is asked
/// once; a failed request is asked again by the next list that needs it.
// keepAlive: the rows of a list come back as the map pans to and fro, and
// reading them again at each pan would cost a request each time.
@Riverpod(keepAlive: true)
class PlaceDigests extends _$PlaceDigests {
  String? _language;
  final _areas = <String>{};
  final _answeredIds = <String>{};
  final _inFlight = <String, Future<void>>{};

  /// Until when the API refuses this client's reads (its quota, shared by
  /// every device behind one address): nothing is asked before.
  DateTime? _pausedUntil;

  bool get _paused {
    final until = _pausedUntil;
    return until != null && ref.read(clockProvider)().isBefore(until);
  }

  @override
  Map<String, PlaceDigest> build() => const {};

  /// Reads the digests of those of [ids] not read yet.
  Future<void> loadIds(List<String> ids, {required String language}) {
    _follow(language);
    if (_paused) return Future.value();
    final missing = [
      for (final id in ids)
        if (!state.containsKey(id) && !_answeredIds.contains(id)) id,
    ];
    if (missing.isEmpty) return Future.value();
    return Future.wait([
      for (var i = 0; i < missing.length; i += maxDigestIds)
        _once('$language:ids:${missing.skip(i).take(maxDigestIds).join(',')}', () async {
          final chunk = missing.skip(i).take(maxDigestIds).toList();
          final digests = await ref
              .read(placeDigestSourceProvider)
              .ofPlaces(chunk, language: language);
          if (!ref.mounted || language != _language) return;
          _answeredIds.addAll(chunk);
          _keep(digests);
        }),
    ]);
  }

  /// Reads the digests of the places inside [area], already on the API's
  /// grid, unless this run read that area already.
  Future<void> loadArea(GeoBounds area, {required String language}) {
    _follow(language);
    if (_paused) return Future.value();
    final key = '${area.south},${area.west},${area.north},${area.east}';
    if (_areas.contains(key)) return Future.value();
    return _once('$language:area:$key', () async {
      final digests = await ref.read(placeDigestSourceProvider).inArea(area, language: language);
      if (!ref.mounted || language != _language) return;
      _areas.add(key);
      _keep(digests);
    });
  }

  /// A change of language drops what was read: the excerpts were in the
  /// other one.
  void _follow(String language) {
    if (_language == language) return;
    _language = language;
    _areas.clear();
    _answeredIds.clear();
    _inFlight.clear();
    if (state.isNotEmpty) state = const {};
  }

  // `whenComplete` waits for a future its callback returns, and `remove`
  // would return this very future, which would then wait for itself:
  // `removeWhere` returns nothing.
  Future<void> _once(String key, Future<void> Function() load) => _inFlight[key] ??= load()
      .catchError((Object e) {
        _log.info('digests not read: $e');
        if (e is GraphQLRateLimitedException && ref.mounted) {
          _pausedUntil = ref.read(clockProvider)().add(e.wait);
        }
      })
      .whenComplete(() => _inFlight.removeWhere((k, _) => k == key));

  void _keep(List<PlaceDigest> digests) {
    if (digests.isEmpty) return;
    final next = {...state, for (final d in digests) d.placeId: d};
    if (next.length > maxKeptDigests) {
      // The oldest first in a map's order of insertion; the areas read go
      // with them, or a list would think it holds what it dropped.
      final drop = next.length - maxKeptDigests ~/ 2;
      next.keys.take(drop).toList().forEach(next.remove);
      _areas.clear();
      _answeredIds.clear();
    }
    state = next;
  }
}

/// [view] widened to the API's grid, as the digests of a list read from the
/// tiles are asked; null when that is wider than the API serves.
GeoBounds? digestAreaOf(GeoBounds view) => digestArea(placesQueryBox(view));

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/favorites/data/favorites_repository.dart';
import 'package:lunaway/features/places/domain/place.dart';

/// The run's filling of the saved places' streets: a failure stays a
/// failure, so it is never read as "none needed one".
void main() {
  test('a fill that fails fails the provider, never reads as none filled', () async {
    final container = ProviderContainer.test(
      overrides: [favoritesRepositoryProvider.overrideWithValue(_BrokenStreets())],
    );
    await expectLater(container.read(favoriteStreetsFilledProvider.future), throwsStateError);
  });
}

final class _BrokenStreets extends Fake implements FavoritesRepository {
  @override
  Future<int> fillStreets(Future<PlaceSummary?> Function(String placeId) lookup) async =>
      throw StateError('unreadable copy');
}

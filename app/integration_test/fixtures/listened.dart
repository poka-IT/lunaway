import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// The value of [provider] once it has one, read while something listens to
/// it, as a screen would. Read alone, an automatically disposed provider that
/// no widget watches is disposed at the next frame, before a stream such as
/// the device's places has emitted, and its future fails with "disposed
/// during loading state, yet no value could be emitted". Online the map draws
/// the places from the tiles, so nothing watches `mapPlacesProvider` any more
/// (the iOS screens tour, audit 8).
Future<T> listened<T>(ProviderContainer container, ProviderListenable<Future<T>> provider) async {
  final subscription = container.listen(provider, (_, _) {});
  try {
    return await subscription.read();
  } finally {
    subscription.close();
  }
}

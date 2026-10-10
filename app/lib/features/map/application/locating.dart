import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locating.g.dart';

/// Whether the map waits for the device's position after the user asked
/// for it (up to the map's own wait): the button shows it turning, and a
/// second tap meanwhile starts no second wait.
// keepAlive: the wait outlives the button (a layout change rebuilds it
// elsewhere), and its end must still reach the state.
@Riverpod(keepAlive: true)
class Locating extends _$Locating {
  @override
  bool build() => false;

  /// Starts a wait; false when one is already under way.
  bool start() {
    if (state) return false;
    state = true;
    return true;
  }

  void stop() => state = false;
}

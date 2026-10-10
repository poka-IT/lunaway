import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_credit_fold.g.dart';

/// Whether the maps' credit has folded into its mark this run.
///
/// The OpenStreetMap Foundation's attribution guidelines (adopted
/// 2021-06-25) let an interactive map's credit collapse "automatically on
/// map interaction such as panning, clicking, or zooming" or "automatically
/// after five seconds", the licence then found from "an '(i)' button in the
/// corner of the map"; and "if attribution is presented to the user upon
/// application startup, it does not need to be presented to the user every
/// time". So the first map shows "© OpenStreetMap" in full, and once it has
/// folded every map after it (the preview, the guidance, the placement)
/// shows the mark alone (`MapCredit`).
// keepAlive: the credit shown once in the run stands for every map opened
// after it, whichever screen holds it.
@Riverpod(keepAlive: true)
class MapCreditFolded extends _$MapCreditFolded {
  @override
  bool build() => false;

  /// The credit has been seen in full: from now on it shows its mark.
  void fold() {
    if (!state) state = true;
  }
}

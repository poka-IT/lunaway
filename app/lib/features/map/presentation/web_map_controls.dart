import 'package:lunaway/features/map/domain/map_hits.dart';

/// Native builds place the map's controls through the plugin's margins;
/// nothing to do here.
void placeWebMapControls({required double top}) {}

/// Native builds have a real long press; nothing to listen for here.
void Function()? listenWebMapLongPress(void Function(double x, double y) onPress) => null;

/// Native builds are touched: a phone or a tablet.
PointerKind webMapPointerKind() => PointerKind.touch;

/// Native builds draw their cursor themselves; nothing to tell the page.
void markPointerOnWebMap({required bool on}) {}

/// Native builds have no pointer that hovers; nothing to listen for.
void Function()? listenWebMapHover(void Function(WebMapHover? hover) onHover) => null;

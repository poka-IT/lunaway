/// Native builds place the map's compass and attribution through the plugin's
/// margins; nothing to do here.
void placeWebMapControls({required double top}) {}

/// Native builds have a real long press; nothing to listen for here.
void Function()? listenWebMapLongPress(void Function(double x, double y) onPress) => null;

import 'package:flutter/widgets.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';

/// Stands in for the web view map in the web build, where the map is
/// maplibre_gl and the web view package is not compiled in.
class WebViewLunaMap extends StatelessWidget {
  const new(this.props, {super.key});

  final LunaMapProps props;

  @override
  Widget build(BuildContext context) =>
      throw UnsupportedError('the web view map runs on macOS and Windows only');
}

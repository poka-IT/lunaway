import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/map/presentation/gl_map.dart';
import 'package:lunaway/features/map/presentation/web_view_map_stub.dart'
    if (dart.library.io) 'package:lunaway/features/map/presentation/web_view_map.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The map engine of the platform: maplibre_gl on Android, iOS and the web,
/// MapLibre GL JS in a web view on macOS and Windows. Linux users have the
/// web app.
Widget buildPlatformMap(BuildContext context, LunaMapProps props) {
  if (kIsWeb) return GlLunaMap(props);
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => GlLunaMap(props),
    TargetPlatform.macOS || TargetPlatform.windows => WebViewLunaMap(props),
    _ => MessageView(icon: AppIcons.map, title: context.t.map.unsupported),
  };
}

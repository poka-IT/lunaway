import 'package:lunaway_nav/src/rust/frb_generated.dart';

/// Loads the guidance library on Android, iOS, macOS and Windows: the one
/// this package's build hook bundled into the app.
Future<void> loadGuidanceLibrary() => RustLib.init();

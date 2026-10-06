/// Turn-by-turn guidance along a route of the Lunaway API: Ferrostar's
/// navigation core and the server's corridor rule, in Rust, and the spoken
/// instructions through the platform's speech engine.
///
/// Call [RustLib.init] once before building a [Guidance]. The library is
/// built for Android and iOS by this package's build hook; elsewhere `init`
/// throws, and the app previews routes without guidance. A test on a
/// desktop host passes the library it built (`cargo build --release` in
/// `rust/`) as an [ExternalLibrary].
library;

export 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary, PlatformInt64Util;

export 'src/rust/api/country.dart';
export 'src/rust/api/engine.dart';
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/voice.dart';

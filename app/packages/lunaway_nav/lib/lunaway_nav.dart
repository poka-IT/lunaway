/// Turn-by-turn guidance along a route of the Lunaway API: Ferrostar's
/// navigation core and the server's corridor rule, in Rust, and the spoken
/// instructions through the platform's speech engine.
///
/// Call [loadGuidanceLibrary] once before building a [Guidance]: the
/// library this package's build hook bundled on Android, iOS, macOS and
/// Windows, the WebAssembly build of `tool/build_web.sh` in a browser. A
/// test on a desktop host may instead pass the library it built
/// (`cargo build --release` in `rust/`) to [RustLib.init] as an
/// [ExternalLibrary].
library;

export 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary, PlatformInt64Util;

export 'src/load.dart' if (dart.library.js_interop) 'src/load_web.dart';
export 'src/rust/api/country.dart';
export 'src/rust/api/engine.dart';
export 'src/rust/frb_generated.dart' show RustLib;
export 'src/voice.dart';

import 'dart:async';
import 'dart:js_interop_unsafe';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart';
import 'package:lunaway_nav/src/rust/frb_generated.dart';
import 'package:web/web.dart' as web;

/// Where the web app serves the WebAssembly build of the crate
/// (`tool/build_web.sh` writes it to `app/web/lunaway_nav/`), relative to
/// the page's base address.
const _root = 'lunaway_nav/lunaway_nav';

/// Loads the guidance library in the browser: the crate compiled to
/// WebAssembly, the same code as on the phones.
///
/// flutter_rust_bridge's own loader is not used: it publishes the module
/// through `new Function(...)`, which the site's Content Security Policy
/// refuses (no `unsafe-eval`). The build script declares the module with
/// `var`, so it lands on `window` by itself, and only the compilation of
/// WebAssembly is asked of the policy (`wasm-unsafe-eval`). The module is
/// built without threads: every call the app makes is synchronous, so no
/// worker starts and the page needs no cross-origin isolation.
Future<void> loadGuidanceLibrary() async {
  final script = web.HTMLScriptElement()..src = '$_root.js';
  final loaded = Completer<void>();
  script.onLoad.first.then((_) => loaded.complete());
  script.onError.first.then((_) {
    if (!loaded.isCompleted) loaded.completeError(StateError('$_root.js did not load'));
  });
  web.document.head!.append(script);
  await loaded.future;
  final init = web.window.getProperty<JSFunction?>('wasm_bindgen'.toJS);
  if (init == null) throw StateError('$_root.js declared no wasm_bindgen');
  final options = JSObject()..setProperty('module_or_path'.toJS, '${_root}_bg.wasm'.toJS);
  await (init.callAsFunction(null, options)! as JSPromise<JSAny?>).toDart;
  await RustLib.init(
    // The analyser reads RustLib with the native types; on the web the
    // parameter is this web ExternalLibrary (the generated code ignores the
    // same false alarm).
    // ignore: argument_type_not_assignable
    externalLibrary: const ExternalLibrary(
      debugInfo: 'web: $_root',
      wasmBindgenName: 'wasm_bindgen',
    ),
  );
}

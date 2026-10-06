import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Builds the guidance crate for the platforms that guide: Android and iOS.
/// Elsewhere (desktop, and the host of `flutter test`) the app previews a
/// route without the engine, so nothing is compiled and no Rust toolchain is
/// needed there.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (os != OS.android && os != OS.iOS) return;
    await const FlutterRustBridgeNativeAssetsBuilder().run(input: input, output: output);
  });
}

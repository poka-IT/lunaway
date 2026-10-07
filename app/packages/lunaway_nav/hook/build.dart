import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Builds the guidance crate for the native platforms that guide: Android,
/// iOS, macOS and Windows. Linux has no app (its users get the web one), and
/// the web loads the WebAssembly build of `tool/build_web.sh` instead, so
/// nothing is compiled for them.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (!const [OS.android, OS.iOS, OS.macOS, OS.windows].contains(os)) return;
    // --locked: the app ships the crates of the committed Cargo.lock,
    // the ones the gates checked, never a fresh resolution.
    await const FlutterRustBridgeNativeAssetsBuilder(extraCargoBuildArgs: ['--locked'])
        .run(input: input, output: output);
  });
}

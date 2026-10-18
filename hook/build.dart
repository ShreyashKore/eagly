import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Builds `rust/` into the `rust_lib_eagly` code asset that Flutter bundles
/// with the app. flutter_rust_bridge's loader opens it by its platform name
/// (`rust_lib_eagly.framework`, `librust_lib_eagly.so`, `rust_lib_eagly.dll`).
void main(List<String> args) async {
  await build(args, (input, output) async {
    await const FlutterRustBridgeNativeAssetsBuilder().run(
      input: input,
      output: output,
    );
  });
}

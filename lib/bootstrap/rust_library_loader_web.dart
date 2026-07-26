import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

/// A null library asks flutter_rust_bridge to load `pkg/openlogtool_core.js`
/// and its WASM module through the generated Web loader.
ExternalLibrary? bundledRustLibrary() => null;

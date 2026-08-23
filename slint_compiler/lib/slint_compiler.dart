/// Compile-time Slint path for Flutter, in pure Dart.
///
/// `dart run slint_compiler <file.slint>` generates a `<file>.g.dart` with one
/// typed wrapper class per exported component (properties, callbacks, render
/// target). The `.slint` source is embedded in the generated file and executed
/// by the `slint_native` interpreter engine at runtime — no Rust codegen, no
/// per-app native build.
library;

export 'src/generator.dart' show generateDart;

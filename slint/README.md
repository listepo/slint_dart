# slint (core)

Abstract render-engine API for Slint on Flutter.

- `lib/` — the Dart-side mirror of `i-slint-core` / `slint-interpreter` concepts: `SlintEngine`, `SlintComponentDefinition`, `SlintComponent`, `SlintRenderTarget`, input events. Pure Dart, no FFI.
- `rust/` — `slint-dart-core`: shared Rust crate wrapping `slint-interpreter` behind a renderer-agnostic API (compile, instantiate, JSON value bridge, event mapping). No C ABI here — the plugin crates own that.

Implementations: `slint_native` (software renderer), `slint_skia` (Skia renderer).

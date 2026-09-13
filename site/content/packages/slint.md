---
title: "slint (core)"
description: "Abstract render-engine API for Slint on Flutter."
weight: 10
---


Abstract render-engine API for Slint on Flutter.

- `lib/` — the Dart-side mirror of `i-slint-core` / `slint-interpreter` concepts: `SlintEngine`, `SlintComponentDefinition`, `SlintComponent`, `SlintRenderTarget`, input events. Pure Dart, no FFI.
  - `SlintComponent.load(path)` returns the generated wrapper registered for that `.slint` (`TodoApp.register()` once at startup); nothing else turns a path into a component.
  - `writeSlintTree(source, files)` writes a wrapper's `slintSource` and `slintFiles` into a temporary directory and returns the entry's path, for backends that compile at runtime — the Slint compiler resolves `import`s and `@image-url`s from disk.
- `rust/` — `slint-dart-core`: the Rust crate every FFI crate shares — event mapping onto `slint::platform::WindowEvent` and the thread check every entry point runs first. No C ABI here — the FFI crates own that.

Implementations: `slint_interpreter` (software renderer), `slint_skia` (Skia renderer).

`SlintView` sizes the target from the layout each frame (physical pixels).
In an unbounded layout (a `Row`, a scrollable) there is no size to report,
so it renders nothing until the layout is bounded — give it an explicit
size there.

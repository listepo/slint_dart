---
title: "slint (core)"
description: "Abstract render-engine API for Slint on Flutter."
weight: 10
---


Abstract render-engine API for Slint on Flutter.

- `lib/` — the Dart-side mirror of `i-slint-core` / `slint-interpreter` concepts: `SlintEngine`, `SlintComponentDefinition`, `SlintComponent`, `SlintRenderTarget`, input events. Pure Dart, no FFI.
- `rust/` — `slint-dart-core`: shared Rust crate wrapping `slint-interpreter` behind a renderer-agnostic API (compile, instantiate, JSON value bridge, event mapping). No C ABI here — the plugin crates own that.

Implementations: `slint_interpreter` (software renderer), `slint_skia` (Skia renderer).

`SlintView` sizes the target from the layout each frame (physical pixels).
In an unbounded layout (a `Row`, a scrollable) there is no size to report,
so it renders nothing until the layout is bounded — give it an explicit
size there.

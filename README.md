# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

## Layout

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `slint/` | `slint` | `slint-dart-core` | Backend-agnostic core: Dart API (engine, component, render targets, input events), the `SlintView` widget, and a shared Rust events module mapping the FFI event encoding onto `slint::platform::WindowEvent`. No interpreter, no codegen. |
| `slint_interpreter/` | — | `slint-dart-interpreter` | Runtime `.slint` path: wraps `slint-interpreter` (compile, instantiate, JSON value bridge, callbacks) behind a renderer-agnostic API. |
| `slint_compiler/` | `slint_compiler` | `slint-compiler-ffi` | Compile-time `.slint` path: `slint-build` codegen in build.rs, per-component typed C ABI. **No slint-interpreter anywhere.** Ships the example's `TodoApp` ABI and doubles as the pattern apps copy for their own components. |
| `slint_native/` | `slint_native` | `slint-native-ffi` | Interpreter backend over FFI: `slint-dart-interpreter` + software renderer (`slint::platform::software_renderer`) → RGBA frames. |
| `slint_skia/` | `slint_skia` | `slint-skia-ffi` | Interpreter + `i-slint-renderer-skia` (GPU) → Flutter external texture. GPU surface plumbing stubbed. |

Two independent ways to render a `.slint` UI:

```
runtime:       .slint file ──▶ slint_interpreter ──▶ slint_native (or slint_skia) ──▶ SlintView
compile-time:  .slint file ──▶ slint-build (build.rs) ──▶ slint_compiler typed ABI ──▶ SlintView
```

`slint_interpreter` renders without `slint_compiler`; `slint_compiler` renders without `slint-interpreter`. Both feed the same `SlintView` widget via `SlintSoftwareRenderTarget`.

## Bindings pipeline

```
Rust extern "C"  →  cbindgen  →  rust/include/<crate>.h  →  ffigen  →  lib/src/bindings.g.dart  →  hand-written wrappers implementing the `slint` package interfaces
```

Regenerate after changing the Rust ABI:

```bash
cd <plugin>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

## Toolchain

- Flutter via mise: `mise exec -- flutter ...`
- Rust via rustup (`cargo`), plus `cargo install cbindgen`

## Status / next steps

- [x] Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline
- [x] `SlintView` widget (blits software frames; lives in the `slint` package)
- [x] Rust→Dart callbacks via `NativeCallable`
- [x] Interpreter path end-to-end (example todo app, smoke-tested)
- [x] Compiled path (`slint_compiler`) with example backend switch (`--dart-define=SLINT_BACKEND=compiled`)
- [ ] Per-platform build glue (cargokit) so `flutter build` compiles the Rust crates
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D); `Texture` widget path

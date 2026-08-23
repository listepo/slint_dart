# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

## Layout

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `slint/` | `slint` | `slint-dart-core` | Backend-agnostic core: Dart API (engine, component, render targets, input events), the `SlintView` widget, and a shared Rust events module mapping the FFI event encoding onto `slint::platform::WindowEvent`. No interpreter, no codegen. |
| `slint_interpreter/` | — | `slint-dart-interpreter` | Runtime `.slint` path: wraps `slint-interpreter` (compile, instantiate, JSON value bridge, callbacks) behind a renderer-agnostic API. |
| `slint_compiler/` | `slint_compiler` | `slint-introspect` | Compile-time `.slint` path, no interpreter: a build_runner builder generates `foo.g.dart` next to each `foo.slint` (typed wrapper per component — properties, callbacks, render target), and the app's build hook (`buildSlintAot`) AOT-compiles the `.slint` files with `slint-build` plus generated C ABI glue into one code asset the wrappers bind to via `@Native`. `slint-introspect` extracts the typed schema driving both. |
| `slint_native/` | `slint_native` | `slint-native-ffi` | Interpreter backend over FFI: `slint-dart-interpreter` + software renderer (`slint::platform::software_renderer`) → RGBA frames. |
| `slint_skia/` | `slint_skia` | `slint-skia-ffi` | Interpreter + `i-slint-renderer-skia` (GPU) → Flutter external texture. GPU surface plumbing stubbed. |

Two independent ways to render a `.slint` UI:

```
runtime:       .slint file ──▶ slint_interpreter ──▶ slint_native (or slint_skia) ──▶ SlintView
compile-time:  .slint file ──▶ build_runner (slint_compiler) ──▶ foo.g.dart ──▶ app hook: slint-build AOT cdylib ──▶ SlintView
```

Both paths feed the same `SlintView` widget via `SlintSoftwareRenderTarget`. The runtime path compiles `.slint` source with `slint-interpreter` inside `slint_native`; the compiled path ships slint-build-generated components in the app's own code asset and involves no interpreter at all.

## Bindings pipeline

```
Rust extern "C"  →  cbindgen  →  rust/include/<crate>.h  →  ffigen  →  lib/src/bindings.g.dart  →  hand-written wrappers implementing the `slint` package interfaces
```

Regenerate after changing the Rust ABI:

```bash
cd <plugin>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

Bindings are generated in `ffi-native` mode: top-level `@Native` functions
resolved against the code asset `package:<pkg>/src/bindings.g.dart` — no
`DynamicLibrary.open`, no load paths.

## Native assets build

The FFI packages (`slint_native`, `slint_skia`) ship a `hook/build.dart`
(Dart native assets). During
`flutter run` / `flutter build` / `flutter test`, the hook builds the
package's crate with cargo — driven through a `bazel_worker` persistent
worker (`slint_build/bin/cargo_worker.dart`) — and bundles the produced
cdylib as a code asset. Shared plumbing lives in the `slint_build` package
(target-triple mapping, Android NDK/iOS/macOS cross-compile env, cache
invalidation over the Rust sources).

Cargo profile defaults to `release`; switch via pubspec user-defines — read
from the workspace-root `pubspec.yaml` in this repo (an app outside a pub
workspace uses its own pubspec). They are part of the hook input, so changing
them correctly invalidates the hook cache:

```yaml
hooks:
  user_defines:
    slint_native:
      profile: debug   # or release (default)
```

## Toolchain

- Flutter via mise: `mise exec -- flutter ...`
- Rust via rustup (`cargo`), plus `cargo install cbindgen`

## Status / next steps

- [x] Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline
- [x] `SlintView` widget (blits software frames; lives in the `slint` package)
- [x] Rust→Dart callbacks via `NativeCallable`
- [x] Interpreter path end-to-end (example todo app, smoke-tested)
- [x] Compiled path (`slint_compiler`): `.slint` → typed `*.g.dart` codegen with example backend switch (`--dart-define=SLINT_BACKEND=compiled`)
- [x] Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define)
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D); `Texture` widget path

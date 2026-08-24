# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

## Layout

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `slint/` | `slint` | `slint-dart-core` | Backend-agnostic core: Dart API (engine, component, render targets, input events), the `SlintView` widget, and a shared Rust events module mapping the FFI event encoding onto `slint::platform::WindowEvent`. No interpreter, no codegen. |
| `slint_interpreter/` | `slint_interpreter` | `slint-interpreter-ffi` (`rust/`), `slint-dart-interpreter` (`interpreter/`) | Runtime `.slint` path: the nested `interpreter/` crate wraps `slint-interpreter` (compile, instantiate, JSON value bridge, callbacks) behind a renderer-agnostic API; `rust/` adds the software renderer (`slint::platform::software_renderer`) and the C ABI → RGBA frames. |
| `slint_generator/` | `slint_generator` | `slint-introspect` | Shared codegen: `slint-introspect` extracts the typed schema from a `.slint` file, and a build_runner builder emits `foo.g.dart` next to each `foo.slint` — one typed class per component (properties, callbacks, render target), one value class per named struct, plus the embedded `.slint` source. Owns the `SlintComponentFactory` base class (`runtime.dart`) that makes the generated API backend-agnostic. |
| `slint_compiler/` | `slint_compiler` | — | AOT backend, no interpreter: a build_runner builder emits `foo.aot.g.dart` — only the `@Native` externs and a `SlintCompilerFactory` per component, with the component/render-target plumbing hand-written in `runtime.dart`. The app's build hook (`buildSlintAot`) AOT-compiles the `.slint` files with `slint-build` plus generated C ABI glue into a staticlib; the app's link hook (`linkSlintAot`) links it into the one code asset those externs bind to, tree-shaking components no reachable Dart code uses (`@RecordUse` + `package:record_use` + `CLinker`). |
| `slint_skia/` | `slint_skia` | `slint-skia-ffi` | Interpreter + `i-slint-renderer-skia` (GPU) → Flutter external texture. GPU surface plumbing stubbed. |
| `slint_build/` | `slint_build` | — | Shared hook plumbing: cargo builds through a `bazel_worker` persistent worker, target-triple mapping, cross-compile env, cache invalidation. Used by every `hook/build.dart`. |

One typed API, two independent backends behind it:

```
                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)
.slint file ──▶ ────┤
                    ├─ runtime:      SlintInterpreterFactory ──────────────────────────┐
                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart (factory)       ├──▶ SlintView
                                     + app hooks: slint-build AOT staticlib, link hook
                                       tree-shakes unused components into the dylib ───┘
```

`await TodoApp.create()` is the whole call site: the generated wrapper's `defaultFactory` picks the backend by build mode, so app code names neither one. Passing a factory explicitly overrides it. Both factories extend the `SlintComponentFactory` base class in `slint_generator`. Both paths feed the same `SlintView` widget via `SlintSoftwareRenderTarget`. The runtime path compiles the embedded `.slint` source with `slint-interpreter` inside the `slint_interpreter` package; the compiled path ships slint-build-generated components in the app's own code asset and involves no interpreter at all.

The path follows the Flutter build mode, and only the matching dylib is bundled: debug builds (including `flutter test`) ship the interpreter (`slint_interpreter_ffi`), release/profile builds ship the AOT dylib (`slint_dart_aot`). The hooks branch on `linkingEnabled`, which Flutter sets exactly for the non-debug modes.

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

The FFI packages (`slint_interpreter`, `slint_skia`) ship a `hook/build.dart`
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
    slint_interpreter:
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
- [x] Typed codegen (`slint_generator`): `.slint` → `*.g.dart`, one API over both backends via `SlintComponentFactory`
- [x] Compiled path (`slint_compiler`): `*.aot.g.dart` + slint-build AOT staticlib; backend follows the build mode (debug → interpreter, release/profile → AOT)
- [x] Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define)
- [x] Component tree-shaking: app link hook relinks the AOT staticlib keeping only components with a recorded use (`@RecordUse` + `package:record_use` + `CLinker`; active behind `FLUTTER_RECORD_USE=true`, keep-all otherwise)
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D); `Texture` widget path

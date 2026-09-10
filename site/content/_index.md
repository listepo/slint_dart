---
title: "Overview"
description: "What slint_dart is, how the pieces fit, and where the docs live."
weight: 1
---

# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

## Layout

A melos monorepo: a pub workspace (root `pubspec.yaml`, which also holds the
melos config) plus a Cargo workspace (root `Cargo.toml`). Packages live under
`packages/`, apps under `examples/`.

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `packages/slint/` | `slint` | `slint-dart-core` | Backend-agnostic core: Dart API (engine, component, render targets, input events), the `SlintView` widget, and a shared Rust events module mapping the FFI event encoding onto `slint::platform::WindowEvent`. No interpreter, no codegen. |
| `packages/slint_interpreter/` | `slint_interpreter` | `slint-interpreter-ffi` (`rust/`), `slint-dart-interpreter` (`interpreter/`) | Runtime `.slint` path: the nested `interpreter/` crate wraps `slint-interpreter` (compile, instantiate, JSON value bridge, callbacks) behind a renderer-agnostic API; `rust/` adds the software renderer (`slint::platform::software_renderer`) and the C ABI → RGBA frames. |
| `packages/slint_generator/` | `slint_generator` | `slint-introspect` | Shared codegen: `slint-introspect` extracts the typed schema from a `.slint` file, and a build_runner builder emits `foo.g.dart` next to each `foo.slint` — one typed class per component (properties, callbacks, render target), one value class per named struct, plus the embedded `.slint` source. Owns the `SlintComponentFactory` base class (`runtime.dart`) that makes the generated API backend-agnostic. |
| `packages/slint_compiler/` | `slint_compiler` | — | AOT backend, no interpreter: a build_runner builder emits `foo.aot.g.dart` — only the `@Native` externs and a `SlintCompilerFactory` per component, with the component/render-target plumbing hand-written in `runtime.dart`. The app's build hook (`buildSlintAot`) AOT-compiles the `.slint` files with `slint-build` plus generated C ABI glue into a staticlib; the app's link hook (`linkSlintAot`) links it into the one code asset those externs bind to, tree-shaking components no reachable Dart code uses (`@RecordUse` + `package:record_use` + `CLinker`). |
| `packages/slint_skia/` | `slint_skia` | `slint-skia-ffi` | Interpreter + `i-slint-renderer-skia` (GPU) → Flutter external texture. GPU surface plumbing stubbed. |
| `packages/slint_testing/` | `slint_testing` | `slint-testing-ffi` | Testing backend (`i-slint-backend-testing`): instantiates a component with no window, renderer, or event loop and exposes its accessibility tree, so tests find elements by label/id/type/role, click them, and assert on properties and a callback log. Runs under plain `dart test`. |
| `packages/slint_patrol/` | `slint_patrol` | — | Patrol (E2E) support: `$.slint(...)` finders over the **live** component's accessibility tree, tapping and typing through real Flutter gestures aimed at each element's on-screen rect. Extends `PatrolTester`, so one test can drive Flutter widgets, Slint elements, and native UI. |
| `packages/slint_build/` | `slint_build` | — | Shared hook plumbing: cargo builds through a `bazel_worker` persistent worker, target-triple mapping, cross-compile env, cache invalidation. Used by every `hook/build.dart`. |
| `examples/todo/` | `todo_example` | — | Todo demo: one typed API (`TodoApp`) over both backends, the app's `hook/build.dart` + `hook/link.dart`, and the `UnusedGadget` tree-shaking canary. |
| `examples/todo_shared/` | `todo_shared` | — | Shared todo-list state (`TodoStore`, seed, title helper) for the example apps — framework-free, tested under `dart test`. |
| `examples/todo_skia/` | `todo_skia_example` | — | The same `ui/todo.slint` on the `slint_skia` backend: compiled by `SkiaSlintEngine` at runtime, model synced from Dart, a `Texture` widget waiting on the GPU plumbing. Builds all of Skia, so CI-only. |

One typed API, two independent backends behind it:

```
                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)
.slint file ──▶ ────┤
                    ├─ runtime:      SlintInterpreterFactory ──────────────────────────┐
                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart (factory)       ├──▶ SlintView
                                     + app hooks: slint-build AOT staticlib, link hook
                                       tree-shakes unused components into the dylib ───┘
```

`SlintComponent.load('ui/todo.slint')` is the whole call site — synchronous, since either backend instantiates in a single FFI call — after one `TodoApp.register()` at startup (per component, so an unregistered one still tree-shakes away). A UI is named by its `.slint` path in every build mode, and the generated wrapper resolves that name to whatever the build compiled: the interpreter compiling the embedded source in debug, the AOT-compiled component in release and profile. The split is generated, not looked up: `defaultFactory` branches on a `const`, so a release binary carries no interpreter path and no copy of the `.slint` text either — the embedded source is referenced only where the interpreter factory is constructed, inside the branch the tree shaker drops. App code names neither backend; passing a factory to `create()` overrides it. `.slint` files live in `ui/`, outside `lib/`, and are never bundled: the builder embeds the source it compiled into `lib/*.g.dart`, and release compiles it into the AOT dylib, so neither mode reads the file. A `.slint` no wrapper was generated from can still be read from the asset bundle and compiled through `SlintComponent.loadAsset`, for an app that deliberately ships one; that needs the interpreter, and is async because reading the bundle is. Both factories extend the `SlintComponentFactory` base class in `slint_generator`. Both paths feed the same `SlintView` widget via `SlintSoftwareRenderTarget`. The runtime path compiles the embedded `.slint` source with `slint-interpreter` inside the `slint_interpreter` package; the compiled path ships slint-build-generated components in the app's own code asset and involves no interpreter at all.

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

The FFI packages (`slint_interpreter`, `slint_skia`, `slint_testing`) ship a
`hook/build.dart` (Dart native assets). During
`flutter run` / `flutter build` / `flutter test` — or `dart test`, for
`slint_testing` — the hook builds the
package's crate with cargo — driven through a `bazel_worker` persistent
worker (`packages/slint_build/bin/cargo_worker.dart`) — and bundles the produced
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

## Platforms

macOS, iOS, and Android build and run today (verified on device simulators
for both mobile platforms, in both backends). The hooks derive everything
per-platform from the build input — Rust target triple, Android NDK clang
wrapper and API level, Apple deployment targets — so no platform-specific
configuration lives in the app. Linux and Windows have target-triple
mappings but are untested.

Per-platform build commands and a measured size comparison live in the
[todo example]({{< relref "examples/todo" >}}) docs.

## Toolchain and workflow

- Flutter via mise: `mise exec -- flutter ...`
- Rust via rustup (`cargo`), plus `cargo install cbindgen`
- Hugo via mise (`mise.toml` pins it): `just docs-serve` previews the docs, `just docs-build` builds them
- `just` (via mise) for the short form: `just` lists recipes, `just check`
  runs what CI runs; `examples/todo/justfile` has the release builds and the
  tree-shaking check. Melos does the package iteration underneath, as a root
  dev dependency — nothing to activate globally:

```bash
mise exec -- dart pub get                       # the whole workspace
mise exec -- dart run melos run analyze         # dart analyze, per package
mise exec -- dart run melos run test            # Dart packages, then Flutter packages and examples/todo
mise exec -- dart run melos run codegen         # ui/*.slint → lib/*.g.dart in the examples
mise exec -- dart run melos run rust:clippy     # every crate except slint-skia-ffi
mise exec -- dart run melos run check           # all of the above plus formatting — what CI runs
```

`melos run` alone lists the scripts. Rust formatting and linting use rustfmt
defaults and the lint levels in the root `Cargo.toml` `[workspace.lints.*]`
tables (`cargo fmt --all`, `cargo clippy --workspace --exclude slint-skia-ffi
--all-targets`). See [Contributing]({{< relref "contributing" >}}) for the full
workflow and the `AGENTS.md` files (root plus each package) for the invariants a change must respect.

## Testing UIs

`slint_testing` runs a component on Slint's testing backend — no window,
renderer, or event loop — and exposes its accessibility tree, so a test finds
elements by label, id, type, or role, clicks them, fills them in, and asserts
on properties and a callback log:

```dart
app.record('add-todo');
app.findById('TodoApp::edit').single.setValue('buy milk');
app.findByLabel('Add').single.click();
expect(app.takeCalls().single.args, ['buy milk']);
```

It needs neither Flutter nor a device: `dart test` builds its crate through
the same native-assets hook. See the package docs.

`slint_patrol` covers the other half — the app a user actually touches.
Slint draws its whole UI into one Flutter widget, so Patrol's `$(...)` sees a
single opaque box; `$.slint(...)` searches the **live** component's tree and
acts through real Flutter gestures aimed at the element's on-screen rect:

```dart
await $.slintById('TodoApp::edit').enterText('buy milk');
await $.slint('Add').tap();
expect($.slintComponent().getProperty('todo-count'), 1);
```

Both describe elements identically, because both come from one query
implementation in `slint-dart-interpreter` that the testing and runtime FFI
crates each expose. Element queries need the interpreter backend, so they work
in debug builds — including `flutter test` and `patrol test` — and not in the
AOT backend of release and profile builds.

## Status / next steps

- [x] Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline
- [x] `SlintView` widget (blits software frames; lives in the `slint` package)
- [x] Rust→Dart callbacks via `NativeCallable`
- [x] Interpreter path end-to-end (example todo app, smoke-tested)
- [x] Typed codegen (`slint_generator`): `.slint` → `*.g.dart`, one API over both backends via `SlintComponentFactory`
- [x] Compiled path (`slint_compiler`): `*.aot.g.dart` + slint-build AOT staticlib; backend follows the build mode (debug → interpreter, release/profile → AOT)
- [x] Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define)
- [x] Component tree-shaking: app link hook relinks the AOT staticlib keeping only components with a recorded use (`@RecordUse` + `package:record_use` + `CLinker`; active behind `FLUTTER_RECORD_USE=true`, keep-all otherwise)
- [x] UI testing (`slint_testing`): accessibility-tree queries, clicks, property and callback assertions on `i-slint-backend-testing`, under plain `dart test`
- [x] E2E testing (`slint_patrol`): Patrol finders over the live component, tapping and typing through real Flutter gestures (interpreter backend only)
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D); `Texture` widget path

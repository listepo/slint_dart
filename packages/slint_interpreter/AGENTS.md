# Agent notes — `slint_interpreter`

The runtime backend: `slint-interpreter` plus the software renderer, behind
a C ABI. Active in debug builds and `flutter test`. Read the root `AGENTS.md`
first.

## What lives here

| Path | Crate / role |
|---|---|
| `interpreter/` | `slint-dart-interpreter`: renderer-agnostic wrapper over upstream `slint-interpreter` — compile, instantiate, JSON value bridge, callbacks — and `elements.rs`, the accessibility-tree query. Shared with `slint_testing` and `slint_skia`. |
| `rust/` | `slint-interpreter-ffi`: the software renderer (`FlutterSoftwarePlatform`, `MinimalSoftwareWindow`) and the `slint_interpreter_*` C ABI. cbindgen → `rust/include/slint_interpreter_ffi.h`. |
| `lib/src/bindings.g.dart` | ffigen output (`@Native`, asset id `package:slint_interpreter/src/bindings.g.dart`). Generated — never hand-edit. |
| `lib/src/interpreter_engine.dart` | `SlintEngine`/`SlintComponent`/render-target implementations over the bindings; `SlintInspectableComponent.queryElements`. |
| `lib/src/factory.dart` | `SlintInterpreterFactory(source)`: the `SlintComponentFactory` the generated wrappers construct in debug. |
| `lib/src/loader.dart` | `useSlintInterpreter()` and the `SlintComponent.loader` hook behind `SlintComponent.loadAsset`. |
| `hook/build.dart` | Builds `slint-interpreter-ffi` via `slint_build`; lists `rust/`, `../slint/rust/`, `interpreter/` as cache dependencies. |

## Commands

```bash
mise exec -- dart analyze .
cd ../../examples/todo && mise exec -- flutter test     # this backend's real tests
cd rust && cbindgen --output include/slint_interpreter_ffi.h && cd .. && mise exec -- dart run ffigen --config ffigen.yaml   # after a C ABI change only
```

No tests of its own: `examples/todo`, `packages/slint_patrol`, and
`packages/slint/test` exercise it.

## Invariants

- **Everything is synchronous.** `compile` and `instantiate` are single
  FFI calls returning plain values. Only `loadAsset` is async, because
  reading the bundle is.
- **This is the only backend that installs `SlintComponent.loader`.** It
  installs itself when a `SlintInterpreterFactory` is constructed or via
  `useSlintInterpreter()`. AOT has no compiler; `loadAsset` in release
  correctly has nowhere to go.
- **`compile` returns components unordered** (`CompilationResult::components()`
  iterates a `HashMap`). Callers select by name; `defs.first` is a coin flip.
- **Element queries live in `interpreter/src/elements.rs`**, not in
  `rust/`. Both this crate and `slint-testing-ffi` call `query_elements` /
  `describe_all` so headless and live tests read identical fields. The
  crate depends on `i-slint-backend-testing` for `search_api` only and never
  installs the testing platform — this crate keeps installing its own
  `FlutterSoftwarePlatform`.
- **Every C entry point is `catch_unwind`-wrapped** and the crate keeps
  `panic = "unwind"`. Errors go to a thread-local string Dart reads back.
- **Callbacks come back through `NativeCallable`** — keep the Dart side
  alive for as long as the component is; dispose order matters. The
  trampolines set `keepIsolateAlive = false`, so a forgotten `dispose`
  cannot pin a test isolate. A handler that throws cannot unwind through
  Rust: the exception goes to `Zone.current.handleUncaughtError` (a failing
  test, `FlutterError` in an app) rather than being swallowed. An argument
  the JSON bridge cannot carry (image, brush) arrives as `null`; enums read
  as their value name.
- **Frames are premultiplied RGBA8888** at the size `setSize` was given,
  in physical pixels (`SlintView` applies the device pixel ratio). The
  render target starts at 0×0 with no buffer — the size a
  `MinimalSoftwareWindow` starts at — so `render()` before `resize()` is
  `false`, not a "buffer size mismatch" against a made-up default.
- **Every entry point checks `slint_dart_core::thread::check()`** (see
  `slint/AGENTS.md`) before anything else; off the owning thread it sets the
  error and returns the failure value, and the `free`s leak rather than drop
  an `Rc` on the wrong thread.
- **Do not merge this crate with `slint-testing-ffi`.** Each dylib has its
  own statically linked Slint so their platforms don't collide
  (`init_no_event_loop()` panics if a platform already exists).

## Traps

- `bindings.g.dart` and `rust/include/*.h` are committed; regenerate
  both together after any `extern "C"` change and commit the result.
- The build hook runs on every `flutter run/build/test` of a dependent
  package; a first build takes minutes. Cargo profile defaults to release
  (see `slint_build`).
- `clippy::not_unsafe_ptr_arg_deref` is allowed at crate level on purpose:
  the C ABI is never called from Rust, and each deref is an explicit
  `unsafe` block.

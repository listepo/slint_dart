# Agent notes — `slint_skia`

The GPU backend skeleton: interpreter + `i-slint-renderer-skia`, meant to
render into a Flutter external texture. Honest skeleton — the interpreter
half is real, the GPU half is stubbed. Read the root `AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `rust/` | `slint-skia-ffi`: `slint_skia_*` C ABI. Compile/instantiate/property bridge are real (via `slint-dart-interpreter`); `render` returns `false`, `texture_id` returns `-1`. |
| `lib/src/skia_engine.dart` | `SkiaSlintEngine`, `SkiaSlintComponentDefinition`, `SkiaSlintComponent`, `SkiaTextureRenderTarget`. `setCallbackHandler`/`invokeCallback`, `textureId`, pointer/key dispatch throw `UnimplementedError`. |
| `lib/src/bindings.g.dart` | ffigen output. Generated in CI from the committed header, not locally. |
| `hook/build.dart` | Builds `slint-skia-ffi` via `slint_build` — which builds **all of Skia**. |

Consumer: `examples/todo_skia`, which drives the raw component and shows
these ceilings on screen until they lift.

## Commands — what runs locally

```bash
mise exec -- dart format --set-exit-if-changed lib/
cd rust && cargo metadata --format-version 1 > /dev/null    # deps resolve
cd rust && cbindgen --output include/slint_skia_ffi.h       # header regenerates
```

**Never locally**: `cargo build/check/clippy` of this crate, `flutter
run/build/test` of anything depending on it, `ffigen`. Building
`slint-skia-ffi` compiles `skia-safe` (10+ GB of artifacts). Root `Cargo.toml`
and the melos `rust:clippy` script exclude it; the melos `analyze` and
`test:flutter` scripts skip it and `todo_skia_example`. `dart analyze .` here
reports ~80 pre-existing warnings in the generated bindings — not a
regression.

## Invariants

- **`SlintComponentFactory.instantiate` must return a
  `SlintSoftwareComponent`**, and this backend renders to a texture, so it
  has no factory and the typed `TodoApp` wrapper cannot run on it. Don't
  fake a factory that returns a non-software component.
- **Ceilings are explicit.** Unimplemented paths throw `UnimplementedError`
  (Dart) or return the documented sentinel (`false`, `-1`) — never a silent
  no-op that looks like success. `examples/todo_skia` relies on the
  exceptions to say what is missing.
- **A file must export exactly one component.** `compile` returns the
  definitions in `HashMap` order, so "the first" would be random:
  `slint_skia_engine_compile` fails with the names when there are several,
  and the Dart `compile` reads the real name back
  (`slint_skia_definitions_name(def, 0)`). `SkiaSlintComponentDefinition
  .dispose` frees the Rust definition; instantiating after that throws.
- **Same rules as the other FFI crates**: `catch_unwind` on every entry
  point, `panic = "unwind"`, thread-local error string, `slint_skia_*` prefix
  (separate namespace from `slint_interpreter_*`).
- The `README.md` "Shortcuts & Ceilings" table is the status of record —
  update it when a ceiling lifts.
- **`cargo machete` flags `slint`, `i-slint-core`, and
  `i-slint-renderer-skia` here as unused** — correctly: `rust/src/lib.rs`
  references none of them yet. They stay declared because the crate's
  reason to exist is the Skia renderer and the GPU work will use them; if
  someone wants the crate buildable locally in the meantime, dropping those
  three lines is what does it (and every "CI-only" note in the repo would
  then change).

## Upgrade path (when the GPU work starts)

Per-platform window adapter (`rust/src/platform/`: Metal on Apple, Vulkan on
Android, GL/D3D elsewhere) binding `slint::platform::WindowAdapter` to
`SkiaRenderer`; export the frame as a Flutter external texture and return
its id; then a callback channel needs an event loop. `slint_interpreter`'s
software platform is the pattern to copy.

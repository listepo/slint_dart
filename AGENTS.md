# Agent notes for slint_dart

Slint ↔ Flutter integration: a pub workspace (root `pubspec.yaml`) plus a
Cargo workspace (root `Cargo.toml`) in one repo. Read the root `README.md`
for the package/crate layout and architecture; each package README covers its
own details. This file holds what an agent needs beyond the docs: commands,
invariants, and the traps.

## Toolchain and commands

Flutter and Dart run through mise; Rust is a plain rustup install.

```bash
mise exec -- flutter test                 # in examples/todo/: both backends' tests
mise exec -- flutter build macos --release  # e2e: codegen + cargo + link hook
mise exec -- flutter build ios --release --no-codesign            # iOS (device, unsigned)
mise exec -- flutter build apk --release --target-platform android-arm64  # Android
mise exec -- dart test                    # in a package dir: its unit tests
mise exec -- flutter test                 # in slint_patrol/: live-component E2E tests
mise exec -- dart analyze .               # per package; workspace-wide is noisy (slint_skia stubs)
cd examples/todo && mise exec -- dart run build_runner build   # regenerate *.g.dart after editing a .slint
cargo fmt --all                                          # Rust formatting (rustfmt defaults, no config file)
cargo clippy --workspace --exclude slint-skia-ffi --all-targets   # Rust linting
```

Keep `cargo fmt --all --check` and that clippy invocation clean. Lint levels
live in the root `Cargo.toml` `[workspace.lints.*]` tables; members opt in
with `[lints] workspace = true`. `slint-skia-ffi` is always excluded from
clippy/test/build — compiling it builds all of Skia (CI-only). FFI crates
allow `clippy::not_unsafe_ptr_arg_deref` at crate level: C ABI entry points
are never called from Rust, and each dereference is an explicit unsafe
block.

Regenerate FFI bindings only after changing a Rust C ABI:

```bash
cd <plugin>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

Generated files (`*.g.dart`, `*.aot.g.dart`, `bindings.g.dart`) are
committed. Regenerate them; never hand-edit.

Cargo builds happen inside the native-assets hooks during any
`flutter run/build/test` — no manual `cargo build`. First builds and
release builds (fat LTO) take minutes; run them in the background.

## Architecture invariants

- **Backend follows build mode.** Debug (incl. `flutter test`) uses the
  interpreter; release/profile uses the AOT dylib. The hooks branch on
  `linkingEnabled`. AOT tests in `examples/todo/test` self-skip under
  `flutter test`; the release build is their e2e check.
- **The AOT ABI contract lives in one place**:
  `slint_compiler/lib/src/generator.dart` (`aotComponentOps`,
  `aotSharedSymbols`, `aotComponentSymbols`, `aotNewExternName`, manifest
  name). The Dart codegen, the Rust glue emitter (`rust_glue.dart`), and
  both hooks all derive from it. A generator test asserts the manifest
  predicts exactly the symbols the glue exports — keep it passing.
- **Tree-shaking pipeline** (release): build hook emits a cargo *staticlib*
  plus `slint_aot_link.json`, routed `ToLinkHook`; the app's `hook/link.dart`
  (`linkSlintAot`) keeps only components whose generated `_new` extern has a
  recorded use and relinks with `CLinker` treeshake. Flutter records uses
  only behind `FLUTTER_RECORD_USE=true` (or
  `flutter config --enable-record-use`); without it, or when recordings hit
  zero externs, the hook deliberately keeps every component — never "fix"
  those keep-all fallbacks away.
- **`UnusedGadget` in `examples/todo/lib/todo.slint` is a deliberate canary**, not
  dead code: it proves tree-shaking by being absent
  (`slint_aot_unused_gadget_*`) from the shipped dylib when the flag is on.
  Do not remove it.
- **`panic = "unwind"` is load-bearing** in the generated AOT crate and the
  FFI crates: every FFI entry point wraps in `catch_unwind`. Switching to
  `abort` to save size turns Rust panics into process aborts.
- **Symbols strip at the final link, not in cargo.** The staticlib must keep
  its symbols for the link hook's `-u`/exported-list tree-shaking; the hook
  strips the final dylib (`-S`, `-x`). Don't add `strip = "symbols"` back to
  the generated Cargo.toml.
- **`CLinker` emits `-framework` flags only with `language:
  Language.objectiveC`** (native_toolchain_c gate). Removing that argument
  breaks the macOS link with undefined CoreText/CoreFoundation symbols.
- **The linker line comes from rustc**, not guesswork: the build hook runs
  cargo with `RUSTFLAGS=--print=native-static-libs` and persists the note
  per target triple next to the generated crate
  (`native-link-flags.<triple>.txt`). rustc only prints it when it actually
  recompiles — if the persisted file is missing and stale, delete the
  crate's `target/` to force a rebuild.
- **Interpreter component definitions are selected by name** —
  `defs.firstWhere((d) => d.name == ...)`. `slint_interpreter`'s `compile`
  collects `CompilationResult::components()`, which iterates a `HashMap`:
  the order is arbitrary and not the order of the file, so `defs.first` is
  a coin flip whenever a `.slint` exports more than one component.
- **`opt-level = "z"` is rejected** for the AOT crate: measured 2.7× slower
  full-frame renders for ~1 MB/arch. Size-tune with fat LTO +
  `codegen-units = 1` only (see slint_compiler README's table).
- **No `.slint` is ever bundled as a Flutter asset, and the generated `load()`
  must stay that way.** Flutter declares assets per package, not per build
  mode (`dartDataAssets`, which could do it from a build hook, is
  `available: false` off master and cannot be forced on by env var or
  config) — so anything listed under `flutter: assets:` for debug convenience
  also ships in release, putting the UI source in the product. The wrapper
  therefore reads the bundle *only* when handed an explicit `path`;
  `load()` with no argument uses the source the builder embedded. An emitter
  test asserts no `loadString(assetPath)` slips back in. `examples/todo`'s
  assetless `flutter:` section and its "nothing reads the bundle unless a path
  says so" test are the regression guards — don't "fix" either.
- **`SlintComponent.load` routes through the `SlintComponent.loader` hook**
  rather than importing a backend, which is what keeps `slint_core.dart` free
  of any Flutter import: reading the bundle is `slint_interpreter`'s job
  (`useSlintInterpreter`, registered from the factory constructor). AOT has no
  runtime compiler, so the generated `load` ignores `path` in release and uses
  the compiled-in component — that fallback is the feature, not a gap to close.
- **Element queries live in `slint-dart-interpreter`** (`elements.rs`), not in
  either FFI crate: `slint-testing-ffi` and `slint-interpreter-ffi` both call
  `query_elements`/`describe_all`, so a headless test and a `slint_patrol`
  test driving the live app read the same fields for the same element. The
  crate depends on `i-slint-backend-testing` for `search_api` only — walking
  the item tree and reading geometry needs no platform, and `elements.rs`
  never installs the testing one.
- **`slint_patrol` maps Slint geometry to Flutter coordinates by dividing by
  the device pixel ratio**, because `SlintView` multiplies by it on the way in
  and Slint's scale factor is never set (so Slint logical == physical). If
  someone wires up `set_scale_factor`, that mapping has to change with it.
- **`pumpAndSettle` never returns with a `SlintView` on screen** — its
  `Ticker` renders every frame, so the tree is never quiescent. `slint_patrol`
  pumps a bounded number of frames (`slintSettle`); don't "fix" it back to
  settling.
- **`slint_testing` sets its own Slint platform.** It calls
  `init_no_event_loop()`, which panics if a platform already exists — safe
  only because `slint-testing-ffi` is a separate dylib with its own
  statically linked copy of Slint, independent of the
  `FlutterSoftwarePlatform` in `slint-interpreter-ffi`. Do not merge the two
  crates. Its clicks go through the accessible *default action*: the
  `single_click`/`double_click` helpers are async and need an event loop.

## Conventions

- Commit messages: conventional-commit style (`feat:`, `test:`, `fix:`),
  imperative subject, body explains the why. Commit only when asked.
- READMEs are the documentation of record; update the affected package
  README (and the root one for cross-cutting changes) in the same change.
- Rust debug/release profile for the crates is a pubspec user-define
  (`hooks.user_defines.<pkg>.profile`) read from the workspace root
  pubspec — independent of Flutter's `--debug`/`--release`.

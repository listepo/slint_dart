# Agent notes for slint_dart

Slint ↔ Flutter integration: a pub workspace (root `pubspec.yaml`) plus a
Cargo workspace (root `Cargo.toml`) in one repo. Read the root `README.md`
for the package/crate layout and architecture; each package README covers its
own details. This file holds what an agent needs beyond the docs: commands,
invariants, and the traps.

## Toolchain and commands

Flutter and Dart run through mise; Rust is a plain rustup install.

```bash
mise exec -- flutter test                 # in example/: both backends' tests
mise exec -- flutter build macos --release  # e2e: codegen + cargo + link hook
mise exec -- dart test                    # in a package dir: its unit tests
mise exec -- dart analyze .               # per package; workspace-wide is noisy (slint_skia stubs)
cd example && mise exec -- dart run build_runner build   # regenerate *.g.dart after editing a .slint
```

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
  `linkingEnabled`. AOT tests in `example/test` self-skip under
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
- **`UnusedGadget` in `example/lib/todo.slint` is a deliberate canary**, not
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
  `defs.firstWhere((d) => d.name == ...)`. `.slint` files export multiple
  components; `defs.first` is whichever comes first in the file.
- **`opt-level = "z"` is rejected** for the AOT crate: measured 2.7× slower
  full-frame renders for ~1 MB/arch. Size-tune with fat LTO +
  `codegen-units = 1` only (see slint_compiler README's table).

## Conventions

- Commit messages: conventional-commit style (`feat:`, `test:`, `fix:`),
  imperative subject, body explains the why. Commit only when asked.
- READMEs are the documentation of record; update the affected package
  README (and the root one for cross-cutting changes) in the same change.
- Rust debug/release profile for the crates is a pubspec user-define
  (`hooks.user_defines.<pkg>.profile`) read from the workspace root
  pubspec — independent of Flutter's `--debug`/`--release`.

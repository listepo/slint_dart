# Agent notes — `slint_generator`

`.slint` → typed Dart wrapper (`foo.g.dart`), backend-agnostic. Read the
root `AGENTS.md` first; the mode-split invariants there are enforced by this
package's emitter and its tests.

## What lives here

| Path | Role |
|---|---|
| `rust/` | `slint-introspect`: compiles a `.slint` with `i-slint-compiler` and dumps the typed public interface as JSON. Pinned to the exact `slint` version the AOT glue uses. |
| `lib/src/introspect.dart` | Runs that tool (cargo-built on first use) and parses the schema. |
| `lib/src/schema.dart`, `names.dart` | Schema types; Slint → Dart identifier mapping (`todo-model` → `todoModel`, `TodoApp`). |
| `lib/src/emitter.dart` | Emits the wrapper: one class per exported component, one value class per struct, `_source`, `defaultFactory`, `create`, `load`, `register`, `assetPath`. Output is `dart format`ted. |
| `lib/src/factory.dart` (`runtime.dart`) | `SlintComponentFactory`, the `abstract base class` both backends extend. |
| `lib/builder.dart`, `build.yaml` | build_runner builder `^ui/{{}}.slint` → `lib/{{}}.g.dart`. |
| `lib/src/package_config.dart` | Which backends the consuming package depends on — decides what `defaultFactory` becomes. |
| `test/emitter_test.dart` | The regression guards listed below. |

## Commands

```bash
mise exec -- dart test        # builds slint-introspect with cargo on first run
mise exec -- dart analyze .
cd ../../examples/todo && mise exec -- dart run build_runner build   # see the output for real
```

## Invariants (each has an emitter test — keep them passing)

- **`defaultFactory` is chosen at codegen, on a `const`.** With both
  backends: `_useCompiled ? aot.<x>Factory : SlintInterpreterFactory(_source)`
  where `_useCompiled` is `const bool.fromEnvironment`-derived
  (`dart.vm.product || dart.vm.profile`). The untaken branch is dead code the
  tree shaker drops. Never make it a runtime lookup.
- **`_source` appears exactly three times**: the declaration, the
  `slintSource` alias, and the one `SlintInterpreterFactory(_source)`
  construction. The AOT path never mentions it, so a release snapshot has no
  `.slint` text. Don't add a `source` parameter to `instantiate`.
- **No bundle access, ever.** No `rootBundle`, no `loadString(assetPath)`.
  `load(path)` checks the path ends in `.slint`, then that it equals
  `assetPath`, then builds through `defaultFactory`. `SlintComponent.loadAsset`
  is the interpreter's job, not the wrapper's.
- **`register()` is per component**, never per file. A `registerTodoSlint()`
  would reference every component's AOT factory and defeat tree-shaking; a
  test asserts no such function is emitted.
- **`assetPath`, `load`, and `register` exist only when there is a
  `defaultFactory`.** A package depending on neither backend (or only
  `slint_skia`) gets `create(factory)` and `slintSource` only — that is why
  `examples/todo_skia` uses `TodoApp.slintSource`.
- **Generated doc comments must not name `defaultFactory` or `_useCompiled`
  in prose** — the tests count identifier mentions with word-boundary
  regexes and a stray mention breaks the count.
- **Formatter is part of the output.** Tests match generated code
  whitespace-insensitively (`containsCode`); a trailing comma the formatter
  adds is not a bug.
- **Component definitions are selected by name**, never `defs.first`: the
  compiler returns them unordered.

## Traps

- Generated identifiers are not checked against Dart keywords; a Slint
  field named `class` produces uncompilable output. Rename in the `.slint`.
- Supported types: numbers, string, bool, named structs, arrays.
  Color/brush/image/enum fail generation with an error on purpose.
- `rust/Cargo.toml` pins `i-slint-compiler = "=1.17.1"`; bumping it means
  bumping the version `slint_compiler/lib/src/rust_glue.dart` writes into the
  generated AOT crate, in the same change.

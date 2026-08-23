# Todo Example

A Slint UI driven through one generated typed API (`TodoApp`), running on
either backend: **interpreter** (runtime compilation via `slint_interpreter`)
or **compiled** (FFI bindings to precompiled Rust).

The Rust crates are built automatically by each package's `hook/build.dart`
(Dart native assets / code assets) — no manual `cargo build`, no dylib paths.

## Codegen

```bash
cd example && dart run build_runner build
```

Two files per `.slint`, both regenerated after editing `lib/todo.slint`:

- `lib/todo.g.dart` — `slint_generator`: the typed `TodoApp` (properties,
  callbacks, render target) plus the embedded `.slint` source. Backend-agnostic.
- `lib/todo.aot.g.dart` — `slint_compiler`: the `@Native` externs and
  `todoAppFactory` for the AOT backend.

## Backends

`main.dart` names no backend at all:

```dart
final app = await TodoApp.create();
```

The generated `TodoApp.defaultFactory` picks one by build mode, matching the
dylib that actually ships (the hooks read `linkingEnabled`, true exactly for
the non-debug modes). Pass a factory explicitly to override it — that is what
the tests do.

### Interpreter — debug builds

Compiles the source embedded in `todo.g.dart` at runtime and renders via
`slint_interpreter`. No runtime asset. The bundle ships only
`slint_interpreter_ffi`.

```bash
cd example && mise exec -- flutter run
```

### Compiled — release/profile builds

Binds straight to the AOT-compiled component, no interpreter. The bundle
ships only `slint_dart_aot`.

```bash
cd example && mise exec -- flutter run --release
```

## Test

Both backends are tested:

```bash
cd example && mise exec -- flutter test
```

- `test/todo_typed_test.dart` — the generated `TodoApp` over the interpreter
  factory
- `test/todo_smoke_test.dart` — the untyped `slint_interpreter` API directly
- `test/todo_compiled_smoke_test.dart` — the same `TodoApp` over the AOT
  factory; self-skips under `flutter test` (always debug, so the AOT dylib
  isn't built) and runs when the AOT asset is present. `flutter build macos
  --release` still verifies the AOT codegen/compile/link end to end.

## Rust debug/release

The Rust crates build with cargo's `release` profile by default (debug Slint
rendering is unusably slow). To build them in debug, set the `profile`
user-define in the pubspec that the hook runner reads — the workspace root
`pubspec.yaml` in this repo (for a standalone app it would be the app's own):

```yaml
hooks:
  user_defines:
    slint_interpreter:
      profile: debug
```

This cargo profile is independent of Flutter's `--debug`/`--release`; the
Flutter mode only decides *which* crate is built (debug → interpreter,
release/profile → AOT).

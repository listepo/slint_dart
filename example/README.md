# Todo Example

A Slint UI that can run via two backends: **interpreter** (runtime compilation via `slint_native`) or **compiled** (FFI bindings to precompiled Rust).

The Rust crates are built automatically by each package's `hook/build.dart`
(Dart native assets / code assets) — no manual `cargo build`, no dylib paths.

## Backends

### Interpreter (default)

Loads `lib/todo.slint`, compiles at runtime, and renders via `slint_native`.

```bash
cd example && mise exec -- flutter run
```

### Compiled

Uses the generated typed `TodoApp` (`lib/todo.g.dart`), no asset load.

```bash
cd example && mise exec -- flutter run --dart-define=SLINT_BACKEND=compiled
```

Regenerate after editing `lib/todo.slint` (the `slint_compiler` builder turns
every `*.slint` in the package into a sibling `*.g.dart`):

```bash
cd example && dart run build_runner build
```

## Test

Both backends are tested:

```bash
cd example && mise exec -- flutter test
```

- `test/todo_smoke_test.dart` — interpreter path
- `test/todo_compiled_smoke_test.dart` — compiled path

## Rust debug/release

The Rust crates build with cargo's `release` profile by default (debug Slint
rendering is unusably slow). To build them in debug, set the `profile`
user-define in the pubspec that the hook runner reads — the workspace root
`pubspec.yaml` in this repo (for a standalone app it would be the app's own):

```yaml
hooks:
  user_defines:
    slint_native:
      profile: debug
```

This is independent of Flutter's own `--debug`/`--release` — hooks don't see
the Flutter build mode.

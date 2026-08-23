# Todo Example

A Slint UI that can run via two backends: **interpreter** (runtime compilation via `slint_interpreter`) or **compiled** (FFI bindings to precompiled Rust).

The Rust crates are built automatically by each package's `hook/build.dart`
(Dart native assets / code assets) — no manual `cargo build`, no dylib paths.

## Backends

The backend follows the Flutter build mode, and only the matching dylib is
bundled (the hooks read `linkingEnabled`, which is true exactly for the
non-debug modes):

### Interpreter — debug builds

Loads `lib/todo.slint`, compiles at runtime, and renders via `slint_interpreter`.
The bundle ships only `slint_interpreter_ffi`.

```bash
cd example && mise exec -- flutter run
```

### Compiled — release/profile builds

Uses the generated typed `TodoApp` (`lib/todo.g.dart`), no interpreter, no
asset load. The bundle ships only `slint_dart_aot`.

```bash
cd example && mise exec -- flutter run --release
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
- `test/todo_compiled_smoke_test.dart` — compiled path; self-skips under
  `flutter test` (always debug, so the AOT dylib isn't built) and runs when
  the AOT asset is present. `flutter build macos --release` still verifies
  the AOT codegen/compile/link end to end.

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

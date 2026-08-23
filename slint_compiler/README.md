# slint_compiler

The AOT backend for the wrappers `slint_generator` emits: `.slint` files
compiled ahead of time with `slint-build` into the app's own code asset —
**no slint-interpreter at runtime**. The interpreter path
(`slint_interpreter`) is untouched and independent.

## How it works

```
             ┌─ slint_generator ─▶ foo.g.dart (typed API, backend-agnostic)
foo.slint ──▶┼─ build_runner ────▶ foo.aot.g.dart (@Native bindings + factory)
             └─ app build hook ──▶ slint-build codegen + C ABI glue ──▶ one cdylib code asset
```

- The typed API and the schema tool live in `slint_generator`; this package
  adds the AOT backend.
- Its build_runner builder turns each `lib/**.slint` into a sibling
  `*.aot.g.dart`: the `@Native` externs for the glue crate's per-component C
  symbols, plus one `SlintComponentFactory` per component
  (`todoAppFactory`). It binds to the code asset
  `package:<app>/<path>.aot.g.dart`.
- The app's `hook/build.dart` calls `buildSlintAot`, which generates a Rust
  crate in hook scratch space (slint-build codegen of every `lib/**.slint`
  plus generated JSON⇄typed C ABI glue), builds it through slint_build's
  cargo worker, and emits the matching code assets. The user-visible artifact
  stays Dart-only. The hook builds only for release/profile
  (`linkingEnabled`); debug builds — including `flutter test` — use the
  `slint_interpreter` package instead and ship no AOT dylib.

## Usage

```yaml
# pubspec.yaml of the app
dependencies:
  ffi: ^2.1.0        # the generated backend uses package:ffi
  hooks: ^2.0.0      # hook/build.dart runs without dev deps
  slint_compiler: ^0.1.0

dev_dependencies:
  build_runner: ^2.16.0
  slint_generator: ^0.1.0
```

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_build.dart';

void main(List<String> args) => build(args, buildSlintAot);
```

Put `.slint` files under `lib/`, then:

```bash
dart run build_runner build
```

`flutter run`/`build`/`test` compiles the native side automatically via the
hook. One-off CLI (writes both libraries; second argument optional, must be
under `lib/`):

```bash
dart run slint_compiler lib/todo.slint lib/todo.g.dart
```

```dart
import 'todo.g.dart';                    // typed API (slint_generator)
import 'todo.aot.g.dart' as aot;         // AOT backend (this package)

final app = await TodoApp.create(aot.todoAppFactory);
app.todoModel = [
  {'title': 'Learn Slint', 'checked': false},
];
```

## Limits

- Supported property/callback types: numbers, string, bool, named structs,
  arrays. Color/brush/image/enum properties fail generation with a clear
  error.
- Component names must be unique across the package (all components share
  one glue dylib).
- A Rust toolchain is required at generation and build time (the schema tool
  and the glue crate are compiled with cargo).

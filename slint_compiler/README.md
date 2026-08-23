# slint_compiler

Generates typed Dart wrappers (`*.g.dart`) from `.slint` files, AOT-compiled
with `slint-build` — **no slint-interpreter at runtime**. The interpreter
path (`slint_native`) is untouched and independent.

## How it works

```
                    ┌─ build_runner ──▶ foo.g.dart (typed classes, @Native bindings)
foo.slint ──▶ schema┤
                    └─ app build hook ─▶ slint-build codegen + C ABI glue ──▶ one cdylib code asset
```

- `rust/` holds `slint-introspect`: compiles the `.slint` with
  `i-slint-compiler` and dumps the full typed public interface (struct
  fields, array element types, callback signatures) as JSON.
- The build_runner builder turns each `lib/**.slint` into a sibling
  `*.g.dart`: one class per exported component with typed property accessors,
  `onX`/`invokeX` per callback, a software `renderTarget`, and the full
  `SlintComponent` interface. It binds via `@Native` to the code asset
  `package:<app>/<path>.g.dart`.
- The app's `hook/build.dart` calls `buildSlintAot`, which generates a Rust
  crate in hook scratch space (slint-build codegen of every `lib/**.slint`
  plus generated JSON⇄typed C ABI glue), builds it through slint_build's
  cargo worker, and emits the matching code assets. The user-visible artifact
  stays Dart-only.

## Usage

```yaml
# pubspec.yaml of the app
dependencies:
  ffi: ^2.1.0        # the generated wrappers use package:ffi

dev_dependencies:
  build_runner: ^2.16.0
  hooks: ^2.0.0
  slint_compiler: ^0.1.0
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
hook. One-off CLI (second argument optional, must be under `lib/`):

```bash
dart run slint_compiler lib/todo.slint lib/todo.g.dart
```

```dart
import 'todo.g.dart';

final app = await TodoApp.create();
app.todoModel = [
  {'title': 'Learn Slint', 'checked': false},
];
app.onAddTodo((args) {
  final text = args[0] as String;
  // ...
  return null;
});
```

## Limits

- Supported property/callback types: numbers, string, bool, named structs,
  arrays. Color/brush/image/enum properties fail generation with a clear
  error.
- Component names must be unique across the package (all components share
  one glue dylib).
- A Rust toolchain is required at generation and build time (the schema tool
  and the glue crate are compiled with cargo).

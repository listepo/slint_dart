# slint_generator

Turns `.slint` files into typed Dart wrappers (`*.g.dart`) that run on **any**
Slint backend. Shared by both paths: the interpreter (`slint_interpreter`) and
the AOT-compiled one (`slint_compiler`).

## How it works

```
foo.slint ──▶ slint-introspect (rust/) ──▶ schema ──▶ build_runner ──▶ foo.g.dart
```

- `rust/` holds `slint-introspect`: compiles the `.slint` with
  `i-slint-compiler` and dumps the full typed public interface (struct fields,
  array element types, callback signatures) as JSON.
- The build_runner builder emits one class per exported component — typed
  property accessors, `onX`/`invokeX` per callback, `renderTarget`, `dispose`
  — plus the `.slint` source, embedded so runtime backends can compile it.
- Instances come from a `SlintComponentFactory`, so the generated API is
  backend-agnostic:

```dart
final app = await TodoApp.create();                            // default backend
final app = await TodoApp.create(SlintInterpreterFactory());   // interpreter
final app = await TodoApp.create(todoAppFactory);              // AOT backend
```

`defaultFactory` is generated from the backends the package depends on: with
both, it follows the build mode (`dart.vm.product`/`dart.vm.profile` — the
same condition as Flutter's `kDebugMode`, so it matches the dylib the build
hooks bundle); with one, it is that one; with neither, `create` requires an
explicit factory. It is created once and shared.

## Two entry points

- `package:slint_generator/runtime.dart` — the `SlintComponentFactory` base
  class. Generated wrappers and apps import this.
- `package:slint_generator/slint_generator.dart` — the build-time API
  (`introspectSlint`, `generateWrapperLibrary`, the schema). Only the builder
  and `slint_compiler` need it.

`SlintComponentFactory` is an `abstract base class`, so a backend must
`extend` it rather than structurally match it — see `SlintInterpreterFactory`
(`slint_interpreter`) and `SlintCompilerFactory` (`slint_compiler`).

## Usage

The generated wrapper imports `runtime.dart`, so this is a regular dependency,
not a dev one:

```yaml
# pubspec.yaml of the app
dependencies:
  slint: ^0.1.0
  slint_generator: ^0.1.0
  slint_interpreter: ^0.1.0   # or slint_compiler for the AOT backend

dev_dependencies:
  build_runner: ^2.16.0
```

```bash
dart run build_runner build
```

```dart
import 'todo.g.dart';

final app = await TodoApp.create(SlintInterpreterFactory());
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
- A Rust toolchain is required at generation time (the schema tool is compiled
  with cargo).

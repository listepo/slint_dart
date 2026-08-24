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
  — plus one class per named struct, plus the `.slint` source, embedded so
  runtime backends can compile it.
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
  const TodoItem(title: 'Learn Slint', checked: false),
];
app.onAddTodo((title) => print(title));
```

## Generated types

Nothing in the generated API is `Object?`. Slint types map to Dart as:

| Slint                                    | Dart                    |
| ---------------------------------------- | ----------------------- |
| `int`                                    | `int`                   |
| `float`, `length`, `duration`, `angle`, `percent` | `double`       |
| `string`                                 | `String`                |
| `bool`                                   | `bool`                  |
| `[T]`                                    | `List<T>`               |
| `struct Foo { … }`                       | generated `class Foo`   |

Each named struct becomes a value class with a const constructor, final
fields, `copyWith`, `==`/`hashCode`, and `toString`. `fromSlint`/`toSlint`
convert to and from the representation the backends speak, and the wrappers
call them for you — a `[TodoItem]` property is a `List<TodoItem>` on both
sides of the accessor.

Callbacks become typed function signatures, using the argument names from the
`.slint` where they are declared:

```slint
callback toggle-todo(index: int, checked: bool);
```

```dart
void onToggleTodo(void Function(int index, bool checked) handler);
void invokeToggleTodo(int index, bool checked);
```

Undeclared argument names fall back to `arg1`, `arg2`, … A callback with a
return type gets it too, converted the same way.

## Limits

- Supported property/callback types: numbers, string, bool, named structs,
  arrays. Color/brush/image/enum properties fail generation with a clear
  error.
- Generated identifiers are not checked against Dart keywords: a Slint field
  or callback argument named `class` or `default` produces a file that does
  not compile. Rename it in the `.slint`.
- A Rust toolchain is required at generation time (the schema tool is compiled
  with cargo).

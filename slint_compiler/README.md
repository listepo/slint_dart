# slint_compiler

Generates typed Dart wrappers (`*.g.dart`) from `.slint` files. Pure Dart —
no Rust codegen, no per-app native build.

## How it works

```
foo.slint ──▶ build_runner (slint_compiler builder) ──▶ foo.g.dart (typed classes)
```

The generator compiles the `.slint` source with the `slint_native`
interpreter engine, introspects each exported component (name, properties
with types, callbacks), and emits one typed wrapper class per component. The
`.slint` source is embedded in the generated file and compiled by the
interpreter at runtime — the only native code is the shared `slint_native`
engine, built automatically by its build hook.

Generated per component:

- `static Future<Foo> create()` — compile embedded source + instantiate
- typed property accessors (`todo-model` → `List<Object?> get todoModel` /
  setter), mapped from Slint types (Number→double, String, Bool, Model→List,
  Struct→Map; everything else `Object?`)
- `onX(handler)` / `invokeX(args)` per callback
- `renderTarget` for `SlintView`, and the full `SlintComponent` interface by
  delegation

## Usage

Add to the app's dev_dependencies and run build_runner — every `*.slint` in
the package gets a sibling `*.g.dart`:

```yaml
dev_dependencies:
  slint_compiler: ^0.1.0
  build_runner: ^2.16.0
```

```bash
dart run build_runner build
```

The builder auto-applies to dependents (`build_to: source`), so generated
files land in the source tree and Flutter builds need no build_runner step.
It shells out to the CLI per file: the generator needs the `slint_native`
FFI engine, whose native asset only exists under `dart run` (build hooks) —
build_runner's AOT build script has none.

One-off CLI (second argument optional, defaults to `<input>.g.dart`):

```bash
dart run slint_compiler todo.slint lib/todo.g.dart
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

- Callback parameter types are not introspectable (slint-interpreter exposes
  names only), so handlers receive `List<Object?>`.
- The embedded source is compiled as a single document; relative `.slint`
  file imports are not resolved at runtime (std-widgets works).

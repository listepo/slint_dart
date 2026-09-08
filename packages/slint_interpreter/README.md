# slint_interpreter

Slint runtime for Flutter via Rust FFI — `slint-interpreter` + software renderer. Bindings generated with cbindgen (Rust → C header) and ffigen (C header → Dart).

## Layout

| Path | Crate | Role |
|---|---|---|
| `interpreter/` | `slint-dart-interpreter` | Renderer-agnostic wrapper over upstream `slint-interpreter`: compile, instantiate, JSON value bridge, callbacks. Also used by `slint_skia`. |
| `rust/` | `slint-interpreter-ffi` | Adds the software renderer and the C ABI (`slint_interpreter_*` symbols) this package binds to. |

## Role

Provides software-rendered component instances through a C ABI:
- **Engine**: Compiles Slint `.slint` source into component definitions (wraps upstream `slint-interpreter`'s `Compiler`)
- **Component**: Instantiated, renderable scene (wraps its `ComponentInstance`)
- **RenderTarget**: Software renderer exposing frames as premultiplied RGBA8888 pixels (wraps `MinimalSoftwareWindow`)
- **`SlintInterpreterFactory`**: the `SlintComponentFactory` subclass
  (`slint_generator`) that backs the typed wrappers — compiles the source
  embedded in a generated `*.g.dart` and instantiates the named component:

```dart
final app = TodoApp.create(SlintInterpreterFactory(TodoApp.slintSource));
```

The factory owns the source and `instantiate` is synchronous — compiling is
one FFI call — so a generated wrapper mentions its embedded source only where
it constructs this factory, and a release build drops both together.

## Loading a `.slint` file at runtime

Compiling at runtime is what this backend is for, so it is the one that can
turn an asset key into a component. `SlintComponent.load(path)` never reads
anything — it answers with the registered wrapper's embedded or compiled-in
code; `SlintComponent.loadAsset` is for a file no wrapper was generated
from. It installs itself as the backend the first time a
`SlintInterpreterFactory` is constructed — which the generated wrappers do —
or call `useSlintInterpreter()` once at startup:

```dart
useSlintInterpreter();
// assets/ui/dashboard.slint is declared under `flutter: assets:`
final component = await SlintComponent.loadAsset('assets/ui/dashboard.slint',
    component: 'Dashboard');
runApp(SlintView(target: component.renderTarget));
```

The path is a Flutter asset key, so the file must be declared under
`flutter: assets:` — which also means it ships, in every build mode. Reach
for this when that is the point (a theme pack, user-supplied UI), not to
avoid regenerating: a generated wrapper already carries its source and
bundles nothing. It is also the one async entry point — reading the bundle
is — where `SlintComponent.load` is synchronous.

`component:` may be omitted only when the file exports exactly one — the
compiler returns them unordered, so with several exports there is no
meaningful "first" and `loadAsset` names what it found instead of guessing. The
engine is created on first use and shared across loads.

Only this backend implements the hook. A release build ships the AOT
backend, which has no compiler, so `SlintComponent.loadAsset` has nothing to
route to — runtime `.slint` loading is an interpreter-only capability, while
`SlintComponent.load` of a registered wrapper works in every mode.

## Inspecting the live component

Components implement `SlintInspectableComponent`: `queryElements(kind, needle)`
returns the accessibility tree — identity, accessible state, and each
element's geometry — as decoded JSON maps, over the
`slint_interpreter_instance_query_elements` entry point.

That is what makes a Slint UI testable from Flutter, which otherwise sees one
opaque widget: `slint_patrol` uses it to find an element and work out where on
screen to tap it. The query itself lives in `slint-dart-interpreter`
(`elements.rs`) and is shared with `slint-testing-ffi`, so headless and live
tests describe elements identically. It comes from `i-slint-backend-testing`'s
`search_api` only — reading the item tree needs no platform, and this crate
keeps installing its own `FlutterSoftwarePlatform`.

## Binding Pipeline

```
packages/slint_interpreter/interpreter/src/lib.rs (interpreter wrapper)
    ↓ used by
packages/slint_interpreter/rust/src/lib.rs (Rust FFI)
    ↓ cbindgen
packages/slint_interpreter/rust/include/slint_interpreter_ffi.h (C ABI)
    ↓ ffigen
packages/slint_interpreter/lib/src/bindings.g.dart (Dart FFI bindings)
    ↓ wrapped by
packages/slint_interpreter/lib/src/interpreter_engine.dart (Dart interface impls)
```

### Regenerate bindings after Rust ABI changes

```bash
cd packages/slint_interpreter/rust
cbindgen --output include/slint_interpreter_ffi.h
cd ../..
dart run ffigen --config packages/slint_interpreter/ffigen.yaml
```

## Status & Next Steps

- [x] Rust FFI layer (engine, definitions, instances, properties, events, rendering)
- [x] Rust→Dart callbacks (registered via `NativeCallable`)
- [x] `SlintView` widget (lives in the `slint` package, consumes `SlintSoftwareRenderTarget.pixels`)
- [x] Build glue: native-assets `hook/build.dart` (cargo via `slint_build`); bundled in debug builds, where the interpreter is the active path

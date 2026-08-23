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
final app = await TodoApp.create(SlintInterpreterFactory());
```

## Binding Pipeline

```
slint_interpreter/interpreter/src/lib.rs (interpreter wrapper)
    ↓ used by
slint_interpreter/rust/src/lib.rs (Rust FFI)
    ↓ cbindgen
slint_interpreter/rust/include/slint_interpreter_ffi.h (C ABI)
    ↓ ffigen
slint_interpreter/lib/src/bindings.g.dart (Dart FFI bindings)
    ↓ wrapped by
slint_interpreter/lib/src/interpreter_engine.dart (Dart interface impls)
```

### Regenerate bindings after Rust ABI changes

```bash
cd slint_interpreter/rust
cbindgen --output include/slint_interpreter_ffi.h
cd ../..
dart run ffigen --config slint_interpreter/ffigen.yaml
```

## Status & Next Steps

- [x] Rust FFI layer (engine, definitions, instances, properties, events, rendering)
- [x] Rust→Dart callbacks (registered via `NativeCallable`)
- [x] `SlintView` widget (lives in the `slint` package, consumes `SlintSoftwareRenderTarget.pixels`)
- [x] Build glue: native-assets `hook/build.dart` (cargo via `slint_build`); bundled in debug builds, where the interpreter is the active path

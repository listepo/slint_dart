# slint_native

Slint runtime for Flutter via Rust FFI — `slint-interpreter` + software renderer. Bindings generated with cbindgen (Rust → C header) and ffigen (C header → Dart).

## Role

Provides software-rendered component instances through a C ABI:
- **Engine**: Compiles Slint `.slint` source into component definitions (wraps `slint_interpreter::Compiler`)
- **Component**: Instantiated, renderable scene (wraps `slint_interpreter::ComponentInstance`)
- **RenderTarget**: Software renderer exposing frames as premultiplied RGBA8888 pixels (wraps `MinimalSoftwareWindow`)

## Binding Pipeline

```
slint_native/rust/src/lib.rs (Rust FFI)
    ↓ cbindgen
slint_native/rust/include/slint_native_ffi.h (C ABI)
    ↓ ffigen
slint_native/lib/src/bindings.g.dart (Dart FFI bindings)
    ↓ wrapped by
slint_native/lib/src/native_engine.dart (Dart interface impls)
```

### Regenerate bindings after Rust ABI changes

```bash
cd slint_native/rust
cbindgen --output include/slint_native_ffi.h
cd ../..
dart run ffigen --config slint_native/ffigen.yaml
```

## Status & Next Steps

- [x] Rust FFI layer (engine, definitions, instances, properties, events, rendering)
- [ ] Cargokit integration for platform-specific build glue (JNI/NDK for Android, Xcode for iOS)
- [ ] SlintView Flutter widget (consumes `SlintSoftwareRenderTarget.pixels`)
- [ ] Rust→Dart callbacks (register via `NativeCallable`, wire in FFI layer)

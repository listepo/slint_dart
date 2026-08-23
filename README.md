# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

## Layout

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `slint/` | `slint` | `slint-dart-core` | Core abstract render engine: Dart API (engine, component definitions/instances, render targets, input events) + shared Rust crate wrapping `slint-interpreter` / `i-slint-core` behind a renderer-agnostic API. |
| `slint_native/` | `slint_native` | `slint-native-ffi` | Dart ↔ Slint via FFI, software renderer (`slint::platform::software_renderer`) → RGBA frames. |
| `slint_skia/` | `slint_skia` | `slint-skia-ffi` | Dart ↔ Rust with `slint-interpreter` + `i-slint-renderer-skia` (GPU) → Flutter external texture. GPU surface plumbing stubbed. |

## Bindings pipeline

```
Rust extern "C"  →  cbindgen  →  rust/include/<crate>.h  →  ffigen  →  lib/src/bindings.g.dart  →  hand-written wrappers implementing the `slint` package interfaces
```

Regenerate after changing the Rust ABI:

```bash
cd <plugin>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

## Toolchain

- Flutter via mise: `mise exec -- flutter ...`
- Rust via rustup (`cargo`), plus `cargo install cbindgen`

## Status / next steps

- [x] Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline
- [ ] Per-platform build glue (cargokit) so `flutter build` compiles the Rust crates
- [ ] `SlintView` widget (blit software frames; `Texture` widget for Skia path)
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D)
- [ ] Rust→Dart callbacks via `NativeCallable`

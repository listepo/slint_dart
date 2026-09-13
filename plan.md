# slint_dart

https://github.com/listepo/slint_dart

Slint UI toolkit ↔ Flutter integration.

| # | Статус | Приоритет | Сложность | Готовность | Агент |
| --- | --- | --- | --- | --- | --- |
| T1 | in progress | P1 | 5 | 70% | Claude Code / claude-opus-5 |

### T1. Skia GPU surface plumbing per platform

Wire Skia GPU surfaces per platform (Metal / GL / Vulkan / D3D) and the Flutter `Texture` widget path. Interpreter and property bridge already work; GPU surface plumbing and texture export are still stubbed.

Scope (creator): all platforms + Flutter external `Texture`, verified in CI only. Local-build ban on `slint-skia-ffi` stays.

**New direct deps — approved by the creator** (both listed in `toolchain.md`; `Cargo.lock` versions kept, nothing else bumped):

1. Rust `raw-window-handle` 0.6 (`std`), all targets — 0.6.2 in `Cargo.lock`. `i_slint_renderer_skia::Surface::new` names `raw_window_handle::Has{Window,Display}Handle` in its signature; neither `slint`, `i-slint-core` nor `i-slint-renderer-skia` re-exports it. Android also builds an `AndroidNdkWindowHandle`.
2. Rust `windows` 0.62, Windows target only — 0.62.2 in `Cargo.lock` (via skia-safe `d3d`). Approved features `Win32_Foundation`, `Win32_Graphics_Direct3D12`, `Win32_Graphics_Dxgi(_Common)`, plus two more of the same crate the code turned out to need, for the creator to confirm: `Win32_Security` (gates `CreateSharedHandle`) and `Win32_Graphics_Direct3D` (`D3D_FEATURE_LEVEL_11_0` for `D3D12CreateDevice`). Creates the D3D12 device, queue, and shared render texture (`CreateCommittedResource` + `CreateSharedHandle`); `skia_safe::gpu::d3d` re-exports the interface types but not their constructors.

Not new crates, FYI: in-repo path dep `slint-dart-core` (`packages/slint/rust`) handles thread pinning and event mapping. `skia_safe` comes through `i_slint_renderer_skia::skia_safe`. System libs: Metal/CoreVideo/IOSurface, NDK `libandroid` + EGL (through Slint), d3d12/dxgi, Linux `libEGL.so.1` (loaded with `dlopen` at attach, so no build-time `libegl-dev`; CI installs Mesa for the test). No new pub packages (`MethodChannel` is in the SDK), CocoaPods or Gradle libs.

**Plan:**

- Rust core (`rust/src/platform/mod.rs`): a Slint `Platform` that creates `SkiaWindowAdapter { Window, SkiaRenderer }`. The instance keeps its adapter (like `slint_interpreter`'s `NEXT_WINDOW` handoff). `set_size`, pointer and key go through `slint-dart-core` and the thread check. `render` = timers + `SkiaRenderer::render`. Returns `false` + error while no surface is attached. Callbacks stay `UnimplementedError`, as a separate ceiling.
- Apple Metal (`darwin/` Swift plugin, `sharedDarwinSource`, `Package.swift` + podspec; `rust/src/platform/metal.rs`): Swift owns the `MTLDevice`/queue, an IOSurface-backed `CVPixelBuffer` and a `CVMetalTextureCache` → `MTLTexture`, plus a `FlutterTexture`. It passes pointers to Dart over the `slint_skia` channel. Dart hands them to Rust over FFI. Rust wraps them in a custom `Surface` via `skia_safe::gpu::mtl` and renders with submit + CPU sync. Dart then calls `textureFrameAvailable`.
- Android EGL (`android/` Java plugin — the example app sets `android.builtInKotlin=false`, so Java needs no Kotlin plugin; `rust/src/platform/android.rs`): `TextureRegistry.createSurfaceProducer()` → `Surface`. Rust exports the JNI `nativeWindowFromSurface` (`ANativeWindow_fromSurface`; Java `System.loadLibrary("slint_skia_ffi")`). Dart then passes the pointer to Rust, and `SkiaRenderer::set_window_handle` runs with an `AndroidNdkWindowHandle`, using Slint's own GL/EGL surface (Slint 1.17.1's `VulkanSurface` has no AndroidNdk arm). `onSurfaceCleanup` → Dart detaches; `onSurfaceAvailable` → Dart allocates and attaches again.
- Windows D3D12 (`windows/` C++ plugin; `rust/src/platform/d3d.rs`): the plugin passes Flutter's adapter LUID. Rust creates a device on that adapter, then a shared texture + NT handle, then a Skia `d3d::BackendContext`. The plugin registers a `GpuSurfaceTexture` (`DxgiSharedHandle`).
- Linux GL (`linux/` C plugin; `rust/src/platform/gl.rs`): Rust sets up a headless EGL pbuffer context and Skia GL (`Interface::new_load_with(eglGetProcAddress)`), renders offscreen and reads back RGBA. The plugin's `FlPixelBufferTexture` copies it. GPU render + CPU copy is a documented ceiling.
- Dart: `pubspec.yaml` `flutter.plugin.platforms`. An async `SkiaTextureRenderTarget.create(component, w, h)` goes over the channel and attaches over FFI; after that, `textureId`, `render`, `resize` and events are sync. New C ABI → `cbindgen` header. `bindings.g.dart` needs ffigen (banned locally), so the new entry points are hand-declared with `@Native` until ffigen runs. `examples/todo_skia` shows `Texture(textureId)`.
- CI (`.github/workflows/ci.yml`): new jobs build `examples/todo_skia`, which compiles `slint-skia-ffi` plus the plugin per target. macos-latest: `flutter build macos --debug` and `flutter build ios --simulator --debug --no-codesign`, plus `cargo clippy -p slint-skia-ffi`. ubuntu-latest: `flutter build linux --debug` and `flutter build apk --debug --target-platform android-arm64`. windows-latest: `flutter build windows --debug`.
- Docs: site `slint_skia.md` "Shortcuts & Ceilings", `packages/slint_skia/AGENTS.md` (cargo-machete note, upgrade path), CONTRIBUTING "What default CI skips", `toolchain.md`.
- Local checks: `dart format`, `dart analyze .`, `cargo metadata` in `packages/slint_skia/rust`, `cbindgen`.

**Status:** code, plugins, example, CI jobs and docs are written; the local checks above pass. Left: the four `skia-*` CI jobs green (the first compile of this code anywhere), fixes from them, and an ffigen run. The Check needs CI, so the card stays here until it is green.

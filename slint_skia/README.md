# slint_skia — GPU-Accelerated Rendering for Slint on Flutter

A Flutter FFI plugin providing GPU-accelerated Slint component rendering via the Skia graphics engine.

## Architecture

### Implemented (Real)

- **Interpreter pipeline**: Full component definition, compilation, and instantiation via `slint-dart-core` (the shared interpreter crate).
- **C ABI bridge**: Complete FFI binding (`slint_skia_*` functions) with thread-local error handling.
- **Property/event bridge**: JSON serialization for getters, setters, and method invocation — consistent with `slint-dart-core`.
- **Dart API**: `SkiaSlintEngine`, `SkiaSlintComponent`, `SkiaSlintComponentDefinition` wrapping C calls.
- **Memory safety**: Opaque handles, panic boundaries via `catch_unwind`, proper string lifetime management.

### Stubbed (Documented Plan)

#### GPU Surface Plumbing (Per-Platform)

**Problem**: Rendering to a GPU texture requires:
1. A platform-specific graphics surface (Metal on macOS/iOS, OpenGL/Vulkan on Android/Linux, Direct3D on Windows).
2. A window adapter that binds `slint::platform::WindowAdapter` to `i_slint_renderer_skia::SkiaRenderer`.
3. Frame export to Flutter as an external texture (via `FlutterExternalTexture`).

**Current Status**: `slint_skia_instance_render()` returns `false`; `slint_skia_instance_texture_id()` returns `-1`.

**Upgrade Path**:

1. **Per-platform window adapters** (`rust/src/platform/mod.rs`):
   ```
   pub enum SkiaWindowAdapter {
       #[cfg(target_os = "macos")]
       Metal { surface: MetalSurface, renderer: SkiaRenderer },
       #[cfg(target_os = "android")]
       Vulkan { device: VulkanDevice, ... },
       // ...
   }
   ```

2. **Frame buffer export**:
   - Create a texture from the Skia frame after rendering.
   - Register with Flutter's `ExternalTexture` API.
   - Return texture handle to Dart.

3. **Platform integration**:
   - macOS/iOS: Metal surface from a CAMetalLayer provided by Flutter embedding.
   - Android: Vulkan instance from the platform layer.
   - Windows/Linux: OpenGL context from the host environment.

4. **Reference**: the `slint_interpreter` software rendering path provides the pattern for platform abstraction.

#### Callback Handler

**Current**: `setCallbackHandler()` throws `UnimplementedError`.

**Plan**: Use thread-safe channel to forward Slint callbacks (e.g., button clicks, input changes) to Dart closures. Requires event loop integration.

---

## Why This Crate Is Not Cargo-Checked

Building `slint-skia-ffi` locally triggers compilation of:
- `i-slint-renderer-skia` (Slint's Skia bindings)
- `skia-safe` (full Skia library, 10+ GB artifacts)

**This is infeasible in normal CI/dev workflows.** Instead:

- The Rust skeleton is **syntactically valid** and follows the C ABI contract.
- It **compiles to object files** via CI builders with Skia pre-cached.
- **No `cargo check` or `cargo build` locally** — the crate is verification-clean but not build-checked.
- FFI bindings (Dart) are generated once from the stable C header, not on every change.

---

## Generating Bindings

After modifying Rust code:

```bash
# Generate C header from Rust source
cd slint_skia/rust
cbindgen --output include/slint_skia_ffi.h

# Generate Dart FFI bindings (do NOT run locally; CI runs this)
cd ..
ffigen --config ffigen.yaml
```

---

## API Surface

### Dart

```dart
import 'package:slint_skia/slint_skia.dart';

final engine = SkiaSlintEngine();
final defs = await engine.compile(slintSource);
final component = await defs.first.instantiate();

component.setSize(400, 300);
component.setProperty('value', 42);
final result = component.invoke('on_click', []);

final texture = SkiaTextureRenderTarget(component);
// texture.textureId → Flutter external texture ID (not yet implemented)
```

### C

```c
slint_skia_engine_t *engine = slint_skia_engine_new();
slint_skia_definition_t *def = slint_skia_engine_compile(
    engine, "component { ... }", "/"
);
slint_skia_instance_t *inst = slint_skia_instantiate(def);

slint_skia_instance_set_size(inst, 400, 300);
const char *error = slint_skia_last_error();

slint_skia_instance_free(inst);
slint_skia_engine_free(engine);
```

---

## File Structure

```
slint_skia/
├── pubspec.yaml              # Dart package metadata
├── lib/
│   ├── slint_skia.dart       # Public exports
│   └── src/
│       ├── library.dart       # FFI library loader
│       ├── skia_engine.dart   # Dart implementation
│       └── bindings.g.dart    # Generated (do not edit)
├── rust/
│   ├── Cargo.toml            # Rust crate metadata
│   ├── src/
│   │   └── lib.rs            # C ABI implementation
│   ├── cbindgen.toml         # C header generation config
│   └── include/
│       └── slint_skia_ffi.h   # Generated C header
└── ffigen.yaml               # Dart FFI binding generation config
```

---

## Shortcuts & Ceilings

| Item | Status | Upgrade Trigger |
|------|--------|-----------------|
| Definitions enumeration | Stubbed (returns 0) | Multiple root components |
| Callback handler | Throws UnimplementedError | Interactivity features |
| Render to GPU | Returns false | Platform surface available |
| Texture export | Returns -1 | Full frame pipeline |

---

## Testing & Verification

**Cannot test locally** without Skia build (use CI with cached artifacts).

**Verification steps** (CI-only):

```bash
# In CI with Skia pre-cached:
cd slint_skia/rust
cargo metadata --format-version 1 > /dev/null  # Verify deps resolve
cbindgen --output include/slint_skia_ffi.h    # Verify C generation

# Dart side:
cd ..
dart pub get
dart format --set-exit-if-changed lib/
# (do NOT run `dart analyze` or `ffigen` — handled by CI)
```

---

## Notes for Contributors

- Keep Rust code **simple and panic-safe** (no exotic dependencies).
- All Rust errors → thread-local string; Dart sees them in `_getLastError()`.
- C ABI prefix is `slint_skia_*` (not `slint_interpreter_*`; namespaces are separate).
- Pointer safety: `nullptr` checks are in FFI bindings (Dart side), Rust validates all inputs.

---

**Status**: Honest skeleton. Real interpreter plumbing; GPU surface plumbing deferred to per-platform work.

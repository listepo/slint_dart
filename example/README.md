# Todo Example

A Slint UI that can run via two backends: **interpreter** (runtime compilation via `slint_native`) or **compiled** (FFI bindings to precompiled Rust).

## Backends

### Interpreter (default)

Loads `todo.slint`, compiles at runtime, and renders via `slint_native`.

```bash
cargo build -p slint-native-ffi
cd example && mise exec -- flutter run
```

### Compiled

Uses `slint_compiler` for static TodoApp bindings, no asset load.

```bash
cargo build -p slint-compiler-ffi
cd example && mise exec -- flutter run --dart-define=SLINT_BACKEND=compiled
```

## Test

Both backends are tested:

```bash
cargo build -p slint-native-ffi
cargo build -p slint-compiler-ffi
cd example && mise exec -- flutter test
```

- `test/todo_smoke_test.dart` — interpreter path
- `test/todo_compiled_smoke_test.dart` — compiled path

All tests pass before submission.

## Debug

Pass dylib overrides via `--dart-define`:

```bash
# Interpreter from custom path
flutter run --dart-define=SLINT_NATIVE_LIB=/path/to/libslint_native_ffi.dylib

# Compiled from custom path (if needed)
flutter run --dart-define=SLINT_BACKEND=compiled
```

Debug entitlements on macOS disable the sandbox, allowing dynamic library loads.

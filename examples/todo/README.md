# Todo Example

A Slint UI driven through one generated typed API (`TodoApp`), running on
either backend: **interpreter** (runtime compilation via `slint_interpreter`)
or **compiled** (FFI bindings to precompiled Rust).

The Rust crates are built automatically by each package's `hook/build.dart`
(Dart native assets / code assets) — no manual `cargo build`, no dylib paths.
In release/profile builds the app's `hook/link.dart` then links the AOT dylib
from the staticlib the build hook produced, tree-shaking components no
reachable Dart code uses (`@RecordUse` recordings). Recording sits behind a
Flutter experiment flag:

```bash
FLUTTER_RECORD_USE=true flutter build macos --release
```

`todo.slint` deliberately exports an `UnusedGadget` component nothing
references: with the flag on, its `slint_aot_unused_gadget_*` symbols are
absent from the shipped `slint_dart_aot` dylib; without it (or with
`recorded_uses` unavailable) every component is kept.

## Codegen

```bash
cd examples/todo && dart run build_runner build
```

Two files per `.slint`, both regenerated after editing `lib/todo.slint`:

- `lib/todo.g.dart` — `slint_generator`: the typed `TodoApp` (properties,
  callbacks, render target), the `TodoItem` value class generated from the
  `.slint` struct, plus the embedded source. Backend-agnostic — `main.dart`
  holds a `List<TodoItem>` and never touches a raw map.
- `lib/todo.aot.g.dart` — `slint_compiler`: the `@Native` externs and
  `todoAppFactory` for the AOT backend.

## Backends

`main.dart` names no backend at all:

```dart
final app = await TodoApp.create();
```

The generated `TodoApp.defaultFactory` picks one by build mode, matching the
dylib that actually ships (the hooks read `linkingEnabled`, true exactly for
the non-debug modes). Pass a factory explicitly to override it — that is what
the tests do.

### Interpreter — debug builds

Compiles the source embedded in `todo.g.dart` at runtime and renders via
`slint_interpreter`. No runtime asset. The bundle ships only
`slint_interpreter_ffi`.

```bash
cd examples/todo && mise exec -- flutter run
```

### Compiled — release/profile builds

Binds straight to the AOT-compiled component, no interpreter. The bundle
ships only `slint_dart_aot`.

```bash
cd examples/todo && mise exec -- flutter run --release
```

## Platforms

macOS, iOS, and Android all build and run. Each platform's Rust cross-compile
is driven by the same hooks — the target triple, the NDK clang wrapper on
Android, and the deployment target on Apple platforms come from the build
input, so there is nothing per-platform to configure:

```bash
mise exec -- flutter build macos --release
mise exec -- flutter build ios --release --no-codesign
mise exec -- flutter build apk --release --target-platform android-arm64
```

Component tree-shaking works on every one: the link hook uses `-dead_strip`
with an exported-symbols list on Apple platforms and `--gc-sections` with a
version script on Android, and `slint_aot_unused_gadget_*` is absent from the
shipped library in all three.

### Measured sizes

One `.slint` file, one screen, arm64 unless noted. Native library is the
Slint code asset the bundle ships — the whole difference between the two
backends:

| Build | macOS | iOS | Android |
| ----- | ----- | --- | ------- |
| Release app (AOT) | 58.5 MB | 23.9 MB | 25.3 MB (APK) |
| ↳ `slint_dart_aot` | 20.1 MB (universal, 2 slices) | 9.7 MB | 9.9 MB |
| Debug app (interpreter) | 134.7 MB | 127.1 MB | 96.8 MB (APK) |
| ↳ `slint_interpreter_ffi` | 26.9 MB | 27.1 MB | 19.6 MB |

The AOT library is roughly 2.8× smaller than the interpreter one, because it
carries compiled components instead of the `.slint` compiler. The rest of
each app is Flutter itself: `Flutter.framework`/`libflutter.so` is 10–39 MB
depending on platform and mode, and debug builds add an unstripped Dart
kernel plus — on Android — a 15 MB Vulkan validation layer.

macOS is the outlier because `flutter build macos` produces a universal
binary; the per-architecture figure is about half.

## Test

Both backends are tested:

```bash
cd examples/todo && mise exec -- flutter test
```

- `test/todo_typed_test.dart` — the generated `TodoApp` over the interpreter
  factory
- `test/todo_smoke_test.dart` — the untyped `slint_interpreter` API directly
- `test/todo_compiled_smoke_test.dart` — the same `TodoApp` over the AOT
  factory; self-skips under `flutter test` (always debug, so the AOT dylib
  isn't built) and runs when the AOT asset is present. `flutter build macos
  --release` still verifies the AOT codegen/compile/link end to end.

## Rust debug/release

The Rust crates build with cargo's `release` profile by default (debug Slint
rendering is unusably slow). To build them in debug, set the `profile`
user-define in the pubspec that the hook runner reads — the workspace root
`pubspec.yaml` in this repo (for a standalone app it would be the app's own):

```yaml
hooks:
  user_defines:
    slint_interpreter:
      profile: debug
```

This cargo profile is independent of Flutter's `--debug`/`--release`; the
Flutter mode only decides *which* crate is built (debug → interpreter,
release/profile → AOT).

# Done

### D1. Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline

Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline.

### D2. SlintView widget

`SlintView` widget (blits software frames; lives in the `slint` package).

### D3. Rust→Dart callbacks via NativeCallable

Rust→Dart callbacks via `NativeCallable`.

### D4. Interpreter path end-to-end

Interpreter path end-to-end (example todo app, smoke-tested).

### D5. Typed codegen (slint_generator)

Typed codegen (`slint_generator`): `.slint` → `*.g.dart`, one API over both backends via `SlintComponentFactory`.

### D6. Compiled path (slint_compiler)

Compiled path (`slint_compiler`): `*.aot.g.dart` + slint-build AOT staticlib; backend follows the build mode (debug → interpreter, release/profile → AOT).

### D7. Build glue: native assets hooks

Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define).

### D8. Component tree-shaking

Component tree-shaking: app link hook relinks the AOT staticlib keeping only components with a recorded use (`@RecordUse` + `package:record_use` + `CLinker`; active behind `FLUTTER_RECORD_USE=true`, keep-all otherwise).

### D9. UI testing (slint_testing)

UI testing (`slint_testing`): accessibility-tree queries, clicks, property and callback assertions on `i-slint-backend-testing`, under plain `dart test`.

### D10. E2E testing (slint_patrol)

E2E testing (`slint_patrol`): Patrol finders over the live component, tapping and typing through real Flutter gestures (interpreter backend only).

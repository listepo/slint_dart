/// Compile-time Slint path for Flutter.
///
/// Components are compiled to Rust at build time by `slint-build`; each
/// component gets a typed FFI surface. No slint-interpreter involved.
library;

export 'src/compiled_todo_app.dart' show CompiledTodoApp;

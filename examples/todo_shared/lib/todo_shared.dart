/// Shared todo-list state for the `examples/todo` and `examples/todo_skia`
/// apps: one framework-free store, so the add/toggle/remove-done rules live
/// in exactly one place and each app only maps to its generated `TodoItem`
/// at the Slint boundary.
library;

export 'src/todo_store.dart';

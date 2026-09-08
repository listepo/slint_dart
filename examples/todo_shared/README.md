# todo_shared

Framework-free todo-list state shared by `examples/todo` and
`examples/todo_skia`: `TodoStore` plus the `TodoEntry` value class, the
seed list, and the AppBar title helper.

Both apps drive the same `.slint` UI (`todo-model`, `add-todo`,
`toggle-todo`, `remove-done`) on different backends. Each keeps its
generated `TodoItem` at the Slint boundary and maps to/from `TodoEntry`
there; the rules (trim-on-add, ignore-empty, bounds-checked toggle,
drop-checked-on-remove) live here once, unit-tested under `dart test`.

`TodoEntry.toSlint()` uses the same map shape as the generated
`TodoItem.toSlint()` (`{'title': ..., 'checked': ...}` keyed by the Slint
field names), so either backend accepts it directly.

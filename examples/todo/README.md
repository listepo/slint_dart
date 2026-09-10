# Todo Example

A Slint UI driven through one generated typed API (`TodoApp`), running on
either backend: **interpreter** in debug (`slint_interpreter`) or **AOT** in
release/profile (`slint_compiler`). Shared list state lives in
`examples/todo_shared`.

```bash
cd examples/todo && mise exec -- flutter run
```

**Full docs:** see the docs site (`just docs-serve`) — Examples → Todo, plus
[Getting started](../../site/content/guides/getting-started.md) and
[Backends](../../site/content/guides/backends.md).

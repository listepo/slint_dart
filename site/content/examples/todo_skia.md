---
title: "Todo Example (Skia backend)"
description: "The `examples/todo` UI on the `slint_skia` backend: the same `ui/todo.slint`"
weight: 20
---


The `examples/todo` UI on the `slint_skia` backend: the same `ui/todo.slint`
(minus the AOT tree-shaking canary), compiled at runtime by `SkiaSlintEngine`
and meant to reach the screen as a Flutter external texture.

This is an honest skeleton, like the backend it sits on. What works today is
the interpreter half: compile, instantiate, property bridge. What the backend
has not grown yet — GPU surface, texture export, callbacks, input — the page
reports on screen in the words of the backend's own `UnimplementedError`s
instead of a blank `Texture`. See `packages/slint_skia/README.md`, "Shortcuts &
Ceilings", for the upgrade path; when `render()` returns true and
`textureId` resolves, `main.dart` switches to `Texture(textureId:)` on its
own.

## Building

`slint_skia`'s build hook compiles `slint-skia-ffi`, which pulls in all of
Skia (10+ GB of artifacts) — so `flutter run`, `flutter build` and
`flutter test` here are **CI-only**, with Skia pre-cached. Locally:

```bash
cd examples/todo_skia && dart run build_runner build   # ui/todo.slint → lib/todo.g.dart
dart analyze .
```

Both run without the native build.

## Codegen

`lib/todo.g.dart` comes from `slint_generator`'s builder, opted into `ui/`
by `build.yaml`. This app uses only what needs no backend factory:
`TodoApp.slintSource` (the embedded `.slint`) and `TodoApp.componentName`.
The list itself lives in the shared `TodoStore` (`examples/todo_shared`,
same seed and rules as `examples/todo`); `main.dart` pushes
`TodoEntry.toSlint()` — the same map shape as the generated `TodoItem` —
via `setProperty('todo-model', ...)`, and the `_Ceilings` fallback renders
`TodoEntry` rows directly. The typed `TodoApp`
wrapper itself expects a `SlintComponentFactory` producing a
software-rendered component; the Skia backend renders to a texture, so it
has no such factory yet and `main.dart` drives the raw `SkiaSlintComponent`.

As in `examples/todo`, nothing under `flutter: assets:` — the source ships
only as the string the builder embedded.

## What differs from `examples/todo`

| | `todo` | `todo_skia` |
|---|---|---|
| Backend | interpreter (debug) / AOT (release) | `SkiaSlintEngine`, every mode |
| Entry point | `SlintComponent.load('ui/todo.slint')` | `SkiaSlintEngine().compile(TodoApp.slintSource)` |
| Frame | `SlintView` over a software render target | `Texture(textureId:)` once the backend provides one |
| Callbacks | delivered | `setCallbackHandler` throws; the list stays Dart-owned |
| Hooks | app-level `hook/build.dart` + `hook/link.dart` | none — `slint_skia`'s own hook builds its crate |
| Tests | `flutter test` locally | `flutter test` in CI only (Skia) |

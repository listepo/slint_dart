# Todo Example (Skia backend)

The `examples/todo` UI on the `slint_skia` backend: same `.slint` model,
compiled at runtime by `SkiaSlintEngine`, aimed at a Flutter external
texture. GPU surface / texture export are still unfinished — builds that pull
Skia are **CI-only**.

```bash
cd examples/todo_skia && dart run build_runner build
dart analyze .
```

**Full docs:** see the docs site (`just docs-serve`) — Examples → todo_skia,
and the [slint_skia](../../site/content/packages/slint_skia.md) package page.

# slint_skia

GPU-oriented Slint backend for Flutter via Rust FFI (`i-slint-renderer-skia`),
meant to render into a Flutter external texture. Interpreter / property
bridge work today; GPU surface and texture export are still the upgrade path.

```yaml
dependencies:
  slint_skia: ^0.1.0
```

**Full docs:** see the docs site (`just docs-serve`) — package page under
Packages (architecture, ceilings, upgrade path), and the
[Backends](../../site/content/guides/backends.md) guide.

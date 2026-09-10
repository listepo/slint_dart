# slint

Abstract render-engine API for Slint on Flutter: `SlintEngine`,
`SlintComponent`, `SlintRenderTarget`, and input events. Pure Dart on the
surface; shared Rust lives in `rust/` (`slint-dart-core`). Implementations:
`slint_interpreter` (software) and `slint_skia` (Skia).

```yaml
dependencies:
  slint: ^0.1.0
```

**Full docs:** see the docs site (`just docs-serve`) — package page under
Packages, plus the [Backends](../../site/content/guides/backends.md) guide.

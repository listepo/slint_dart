# slint_compiler

AOT backend for the wrappers `slint_generator` emits: `.slint` files compiled
ahead of time with `slint-build` into the app's own code asset — **no
slint-interpreter at runtime**. The interpreter path is independent.

```yaml
dependencies:
  slint_compiler: ^0.1.0
```

**Full docs:** see the docs site (`just docs-serve`) — package page under
Packages (pipeline, tree-shaking, size breakdown), and the
[Backends](../../site/content/guides/backends.md) guide.

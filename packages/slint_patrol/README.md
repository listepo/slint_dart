# slint_patrol

Drive Slint UIs from [Patrol](https://patrol.leancode.co) tests. Slint paints
into one Flutter widget, so Patrol's `$(...)` alone is not enough — this
package adds `$.slint(...)` finders over the live accessibility tree and
real Flutter gestures.

```yaml
dev_dependencies:
  slint_patrol: ^0.1.0
```

**Full docs:** see the docs site (`just docs-serve`) — package page under
Packages, and the [Testing](../../site/content/guides/testing.md) guide.

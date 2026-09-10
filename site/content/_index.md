---
title: "slint_dart"
layout: hextra-home
---

{{< hextra/hero-headline >}}
  Slint UI toolkit ↔ Flutter
{{< /hextra/hero-headline >}}

{{< hextra/hero-subtitle >}}
  One typed API over interpreter and AOT backends — plus headless and on-device UI testing.
{{< /hextra/hero-subtitle >}}

{{< hextra/hero-button text="Getting started" link="guides/getting-started" >}}

## Explore

{{< cards >}}
  {{< card link="guides" title="Guides" icon="book-open" subtitle="Getting started, backends, and testing" >}}
  {{< card link="packages" title="Packages" icon="cube" subtitle="What each package does and when to use it" >}}
  {{< card link="examples" title="Examples" icon="template" subtitle="Todo apps on each backend" >}}
  {{< card link="contributing" title="Contributing" icon="sparkles" subtitle="Workflow, commands, and PR checklist" >}}
{{< /cards >}}

## Layout

A melos monorepo: a pub workspace (root `pubspec.yaml`) plus a Cargo workspace
(root `Cargo.toml`). Packages live under `packages/`, apps under `examples/`.

One typed API, two independent backends behind it:

```
                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)
.slint file ──▶ ────┤
                    ├─ runtime:      SlintInterpreterFactory
                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart + app hooks
```

Start with [Getting started](guides/getting-started/), then the
[package reference](packages/) and [backends guide](guides/backends/).

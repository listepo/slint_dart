---
title: "Backends"
description: "Interpreter vs AOT, build modes, tree-shaking."
weight: 20
---

One typed API, two independent backends behind it. The generated wrapper's
`defaultFactory` follows the Flutter build mode, exactly like the hooks that
decide which dylib ships — interpreter in debug, AOT in release/profile.

## Interpreter (debug)

Compiles the source embedded in `foo.g.dart` at runtime and renders via
`slint_interpreter`. No runtime asset. The bundle ships only
`slint_interpreter_ffi`.

```bash
cd examples/todo && mise exec -- flutter run
```

A `.slint` no wrapper was generated from can still be read from the asset
bundle and compiled at runtime through `SlintComponent.loadAsset` — async,
because reading the bundle is, and interpreter-only, because a release build
has no compiler. See the [interpreter package]({{< relref "packages/slint_interpreter" >}}).

## AOT (release/profile)

Binds straight to the AOT-compiled component, no interpreter. The bundle
ships only `slint_dart_aot`.

```bash
cd examples/todo && mise exec -- flutter run --release
```

The app's `hook/build.dart` calls `buildSlintAot`: slint-build codegen of
every `ui/**.slint` plus generated C ABI glue, built as a staticlib. The
app's `hook/link.dart` calls `linkSlintAot`: relinks the final dylib from
that staticlib, keeping only the components the app uses. See the
[AOT package]({{< relref "packages/slint_compiler" >}}) for the pipeline,
the release-size table, and the tree-shaking mechanism.

Component tree-shaking works behind Flutter's record-use flag:

```bash
FLUTTER_RECORD_USE=true flutter build macos --release
```

Without recordings every component is kept — the deliberate keep-all
fallback. The example's `UnusedGadget` component exists to prove the
mechanism: exported and compiled like any other, referenced by no Dart code,
and absent from the shipped dylib when the flag is on.

## Adding a backend

A backend extends `SlintComponentFactory` (see the
[codegen package]({{< relref "packages/slint_generator" >}})) and is passed
to the wrapper's `create()` — `defaultFactory` just picks one from the
package's dependencies at codegen time.

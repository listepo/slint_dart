---
title: "Getting started"
description: "Toolchain, first run, first test."
weight: 10
---

## Prerequisites

- Flutter and Dart through [mise](https://mise.jdx.dev): `mise install`
  reads `mise.toml`. Every Dart/Flutter command is `mise exec -- ...`.
- Rust through rustup, plus `cargo install cbindgen` (only for C ABI changes).
- A C toolchain (Xcode command line tools / NDK) for the app link step.
- Hugo through mise (`mise.toml` pins it) for the docs site: `just docs-serve`.

```bash
mise exec -- dart pub get        # resolves the whole workspace, melos included
```

## Run the example

```bash
cd examples/todo && mise exec -- flutter run
```

`main.dart` names the UI by its `.slint` path and no backend at all:

```dart
TodoApp.register();                                  // once, in main()
final TodoApp app = SlintComponent.load('ui/todo.slint');   // synchronous
```

Debug builds (including `flutter test`) use the interpreter backend;
release/profile builds use the AOT backend. See [Backends]({{< relref "backends" >}}).

## Run the tests

```bash
just check   # what CI runs: analyze, cargo fmt --check, clippy, tests
```

Or per package: `cd packages/<pkg> && mise exec -- dart test`,
`cd examples/todo && mise exec -- flutter test`.

First runs are slow: `flutter test` and `slint_testing`'s `dart test` build
their Rust crates through the native-assets hooks (release profile, minutes).
Nothing needs a manual `cargo build`.

## Regenerate after editing a `.slint`

`.slint` files live in `ui/`; generated Dart lands in `lib/`:

```bash
cd examples/todo && mise exec -- dart run build_runner build
```

See the [codegen package]({{< relref "packages/slint_generator" >}}) for what
each generated file holds.

## What never runs locally

`slint_skia`'s crate pulls in all of Skia. `cargo build/check/clippy` of
`slint-skia-ffi`, and `flutter run/build/test` of `examples/todo_skia`, are
CI-only. The melos scripts already skip them; `dart run build_runner build`
and `dart analyze .` are the local checks for `todo_skia`.

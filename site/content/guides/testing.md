---
title: "Testing UIs"
description: "Headless slint_testing and live slint_patrol."
weight: 30
---

Two halves, one element model. Both describe elements identically because
both descriptors come from one Rust implementation in
`slint-dart-interpreter`.

## Headless: slint_testing

A component on Slint's testing backend — no window, renderer, or event loop:

```dart
final app = SlintTestApp.compile(source, component: 'TodoApp');
addTearDown(app.dispose);

app.record('add-todo');
app.findById('TodoApp::edit').single.setValue('buy milk');
app.findByLabel('Add').single.click();

expect(app.takeCalls().single.args, ['buy milk']);
```

Runs under plain `dart test` — no Flutter, no device. Reach for it to check
a component's logic. See the [testing package]({{< relref "packages/slint_testing" >}}).

## Live: slint_patrol

Patrol finders over the live component in a real widget tree, tapping and
typing through real Flutter gestures:

```dart
await $.slintById('TodoApp::edit').enterText('buy milk');
await $.slint('Add').tap();
expect($.slintComponent().getProperty('todo-count'), 1);
```

`SlintView` renders on a `Ticker` every frame, so the tree never settles —
use `slintSettle()` (a bounded handful of frames) where a Flutter-only test
would call `pumpAndSettle`. Element queries need the interpreter backend
(debug builds, including `flutter test` and `patrol test`). See the
[Patrol package]({{< relref "packages/slint_patrol" >}}).

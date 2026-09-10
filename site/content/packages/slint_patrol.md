---
title: "slint_patrol"
description: "Drive Slint UIs from [Patrol](https://patrol.leancode.co) tests."
weight: 35
---


Drive Slint UIs from [Patrol](https://patrol.leancode.co) tests.

Slint renders its whole UI into a single Flutter widget, so Flutter's own
finders — and Patrol's `$(...)` — see one opaque box. There is no widget for
the button you want to press. This package adds `$.slint(...)` finders that
search the **live component's accessibility tree** instead, then tap and type
through **real Flutter gestures** aimed at where the element actually sits on
screen. The input travels the same path a user's finger does: gesture →
`SlintView`'s `Listener` → Slint. No test-only side door.

```dart
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint_patrol/slint_patrol.dart';

patrolWidgetTest('adding a todo', ($) async {
  await $.pumpWidget(const TodoApp());
  await $.slintSettle();

  await $.slintById('TodoApp::edit').enterText('buy milk');
  await $.slint('Add').tap();

  expect($.slintComponent().getProperty('todo-count'), 1);
});
```

It extends `PatrolTester`, so it composes with the rest of Patrol: the same
test can drive Flutter widgets with `$(...)`, Slint elements with
`$.slint(...)`, and native UI with Patrol's `$.native`.

## Finding elements

| Method | Matches |
| --- | --- |
| `$.slint(label)` | the accessible label — a button's text, a checkbox's caption |
| `$.slintById(id)` | an element id qualified by its component, `TodoApp::edit` |
| `$.slintByType(name)` | the element's type, `Button`, `LineEdit` |
| `$.slintByRole(role)` | the accessible role, `Button`, `Checkbox`, `TextInput` |
| `$.slintAll()` | every element in the tree |

Prefer `$.slint(label)`: it matches what a user reads. `$.slintAll()` walks
into the widgets' own implementation — a `LineEdit` is followed by the
`Rectangle`, `TextInput`, and `Text` that make it up — which is useful for
exploring an unfamiliar screen and noisy for assertions.

Finders are lazy, like Patrol's. Nothing is queried until you await an action
or read `current`, `exists`, or `count`.

```dart
await $.slint('Save').tap();                  // waits, then taps
await $.slintByType('Text').first.tap();      // narrow an ambiguous match
$.slint('Save').exists;                       // right now, no waiting
await $.slint('Save').resolve();              // the SlintElementInfo itself
```

`resolve()` throws when several elements match, so a test never silently acts
on an arbitrary one — narrow with `first` or `at(index)` when that is what you
mean.

## Waiting, and why not `pumpAndSettle`

`SlintView` drives a `Ticker` that renders every frame, so the widget tree
**never goes quiescent** and `pumpAndSettle` always times out. Use
`$.slintSettle()` — a bounded handful of frames — wherever a Flutter-only test
would settle.

Actions wait on their own: `tap()` and `enterText()` pump until the element
exists *and* has a non-zero size, because Slint computes geometry during
layout and an element found before the first frame reports an empty rect that
is not yet somewhere you can click. The budget comes from Patrol's
`config.visibleTimeout`, spent as frames rather than wall-clock time — the
test clock is fake, so real waiting would simply hang.

## Typing

`enterText` taps the element to focus it, then types through the text input
connection a focused `SlintView` holds on every platform — the path a soft
keyboard takes, and the one the desktop text input plugin takes behind a
hardware keyboard. It is the app's real input path. `SlintView` maps the
edits to characters, backspace and enter, which is the limit here too.

## Properties and callbacks

`$.slintComponent()` returns the live component for reading and writing
properties and invoking callbacks, through the same JSON bridge the rest of
the repo uses:

```dart
$.slintComponent().setProperty('title', 'Groceries');
expect($.slintComponent().getProperty('todo-count'), 3);
```

## Which backend works

Element queries need `SlintInspectableComponent`, which the **interpreter**
backend implements — that is what debug builds use, including `flutter test`
and `patrol test`. The AOT backend of release and profile builds does not
implement it yet, and finders throw a message saying so rather than failing
obscurely.

## How it relates to slint_testing

[`slint_testing`]({{< relref "packages/slint_testing" >}}) tests a component **headlessly**: no
window, no renderer, no Flutter. It is the fast unit-level tool, and it owns
the element model — `SlintElementInfo`, which this package reuses.

`slint_patrol` tests the **running app**: a real widget tree, real geometry,
real gestures. Both describe elements identically because both descriptors
come from one Rust implementation in `slint-dart-interpreter`, exposed by the
testing backend's FFI and the runtime backend's alike.

Reach for `slint_testing` to check a component's logic, and `slint_patrol` to
check that the app a user touches actually works.

## Layout

```
lib/slint_patrol.dart           public API
lib/src/slint_finder.dart       SlintFinder: query, wait, tap, type
lib/src/patrol_tester_ext.dart  the $.slint* methods on PatrolTester
```

No Rust of its own: the query entry point lives in `slint_interpreter`.

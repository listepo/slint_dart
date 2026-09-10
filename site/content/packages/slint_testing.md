---
title: "slint_testing"
description: "Test Slint UIs from Dart, through the accessibility tree."
weight: 45
---


Test Slint UIs from Dart, through the accessibility tree.

A component is compiled and instantiated on Slint's testing backend
(`i-slint-backend-testing`) — no window, no renderer, no event loop — and
exposed as elements you can find, click, fill in, and assert on. Tests
describe what a user can perceive and do, not which pixels changed.

```dart
import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';

void main() {
  test('adding a todo tells the app what to add', () {
    final app = SlintTestApp.compile(
      File('ui/todo.slint').readAsStringSync(),
      component: 'TodoApp',
      path: 'ui/todo.slint',
    );
    addTearDown(app.dispose);

    app.record('add-todo');
    app.findById('TodoApp::edit').single.setValue('buy milk');
    app.findByLabel('Add').single.click();

    expect(app.takeCalls().single.args, ['buy milk']);
  });
}
```

Runs under plain `dart test` — no Flutter, no device, no golden files. The
native library is built by the package's own build hook.

## Finding elements

| Method | Matches |
| --- | --- |
| `findByLabel(label)` | the accessible label — a button's text, a checkbox's caption |
| `findById(id)` | an element id qualified by its component, `TodoApp::edit` |
| `findByType(name)` | the element's type, `Button`, `LineEdit` |
| `findByRole(role)` | the accessible role, `Button`, `Checkbox`, `TextInput` |
| `findAll()` | every element in the tree |

Each returns a `List<SlintElement>` carrying `id`, `typeName`, `role`,
`label`, `value`, `placeholder`, `description`, `checked`, `checkable`,
`enabled`, `itemIndex`, `itemCount`, and the element's `x`, `y`, `width`,
`height` in Slint logical pixels relative to the window.

Those fields come from `SlintElementInfo`, the element model this package
owns. `slint_patrol` reuses it for the live app, and both are filled in by one
Rust implementation in `slint-dart-interpreter`, so the same element reads the
same headlessly and on screen. Geometry is only meaningful once the component
has been laid out, which headless tests never trigger — it is there for
`slint_patrol`, which needs it to know where to click.

The tree is the *whole* tree: it descends into the widgets' own
implementation, so a `LineEdit` is followed by the `Rectangle`, `TextInput`,
and `Text` that make it up, and a widget repeats its role on the inner
elements implementing it. Prefer `findByLabel` and `findById` — they name
what the test is actually about; `findAll` is for exploring an unfamiliar
component.

Results are a snapshot, and each query replaces the previous one. An element
therefore belongs to the query that produced it: acting on one from an
earlier query throws, rather than silently acting on whatever now sits at
that position. Query, act, and query again.

## Interacting

`click()` invokes the element's accessible **default action** — pressing a
button, toggling a checkbox. `setValue(String)` sets its accessible value —
typing into an input, moving a slider. Both are synchronous: the testing
backend runs without an event loop, so the async pointer-event helpers that
need one are deliberately not exposed.

Using a component or element after `dispose()` throws (`SlintTestException`)
— the Dart side never sends a freed handle back into native code.

`elapse(Duration)` advances the backend's mock clock, driving animations and
timers without waiting in real time.

## Properties and callbacks

`getProperty` / `setProperty` / `invoke` cross the same JSON bridge the
interpreter uses, so Dart maps and lists map onto Slint structs and models.

Callbacks are asserted through a call log rather than a Dart closure:
`record(name)` starts recording invocations of that callback — replacing
whatever handler the component had — and `takeCalls()` returns the calls
since the last drain and clears the log. That keeps the whole surface
synchronous and free of callback trampolines.

## Choosing the component

`component:` may be omitted only when the source exports exactly one.
The compiler returns components unordered, so with several exports there is
no meaningful "first" to fall back on; `compile` throws and names what it
found instead of picking one arbitrarily.

## Layout

```
lib/slint_testing.dart      public API
lib/src/testing.dart        SlintTestApp, SlintElement, SlintCall
lib/src/bindings.g.dart     generated ffigen bindings — do not hand-edit
hook/build.dart             builds the Rust crate as a native asset
rust/                       slint-testing-ffi: the C ABI over the testing backend
```

The Rust crate links its own copy of Slint, so its testing platform is
independent of the software platform `slint_interpreter` installs. Reuses
`slint-dart-interpreter` for compilation, the JSON property bridge, and the
element query itself.

## Testing the running app instead

This package tests a component headlessly — fast, but not the app a user
touches. [`slint_patrol`]({{< relref "packages/slint_patrol" >}}) covers that: Patrol finders over
the live component in a real widget tree, tapping and typing through real
Flutter gestures.

import 'dart:io';

import 'package:test/test.dart';
import 'package:todo_skia_example/todo.g.dart';

/// The wrapper embeds a copy of the `.slint` source, so an edit to the source
/// without a rebuild leaves the app silently running the old UI. Nothing else
/// catches that — the stale file still compiles.
///
/// Runs only where `slint-skia-ffi` can be built (CI with Skia cached):
/// `flutter test` runs every dependency's build hook first, and this app
/// depends on `slint_skia`.
void main() {
  test('the generated wrapper embeds the current todo.slint', () {
    final onDisk = File('ui/todo.slint').readAsStringSync();
    expect(
      TodoApp.slintSource,
      onDisk,
      reason: 'lib/todo.g.dart is stale — run `dart run build_runner build`',
    );
  });

  test('the Skia example carries no tree-shaking canary', () {
    // UnusedGadget proves AOT tree-shaking in examples/todo; there is no AOT
    // here, and the Skia engine enumerates a single definition anyway.
    expect(TodoApp.slintSource, isNot(contains('UnusedGadget')));
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// The wrapper embeds a copy of the `.slint` source, so an edit to the source
/// without a rebuild leaves the app silently running the old UI. Nothing else
/// catches that — the stale file still compiles.
void main() {
  test('the generated wrapper embeds the current todo.slint', () {
    final onDisk = File('lib/todo.slint').readAsStringSync();
    expect(
      TodoApp.slintSource,
      onDisk,
      reason: 'lib/todo.g.dart is stale — run `dart run build_runner build`',
    );
  });
}

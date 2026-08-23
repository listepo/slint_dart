import 'dart:io';
import 'package:slint_native/slint_native.dart';
import 'package:test/test.dart';

void main() {
  test('compiles todo.slint', () async {
    // Find todo.slint relative to current directory
    final cwd = Directory.current.path;
    var slintPath = '$cwd/lib/todo.slint';
    if (!File(slintPath).existsSync()) {
      // Try one level up (in case test is run from repo root)
      slintPath = '$cwd/example/lib/todo.slint';
    }
    if (!File(slintPath).existsSync()) {
      throw StateError('todo.slint not found. Checked: $cwd/lib/todo.slint and $cwd/example/lib/todo.slint');
    }

    final source = File(slintPath).readAsStringSync();
    final engine = NativeSlintEngine();
    final defs = await engine.compile(source, path: 'todo.slint');

    expect(defs, isNotEmpty);
    expect(defs.first.name, 'TodoApp');

    defs.first.dispose();
    engine.dispose();
  });

  test('instantiates and syncs model', () async {
    final cwd = Directory.current.path;
    var slintPath = '$cwd/lib/todo.slint';
    if (!File(slintPath).existsSync()) {
      slintPath = '$cwd/example/lib/todo.slint';
    }
    var slintFile = File(slintPath);

    final source = slintFile.readAsStringSync();
    final engine = NativeSlintEngine();
    final defs = await engine.compile(source, path: 'todo.slint');
    final component = defs.first.instantiate() as NativeSlintComponent;

    // Set model
    final model = [
      {'title': 'buy milk', 'checked': false},
      {'title': 'ship demo', 'checked': true},
    ];
    component.setProperty('todo-model', model);

    // Get model back
    final back = component.getProperty('todo-model') as List<Object?>;
    expect(back.length, 2);
    expect((back[0] as Map<Object?, Object?>)['title'], 'buy milk');
    expect((back[0] as Map<Object?, Object?>)['checked'], false);
    expect((back[1] as Map<Object?, Object?>)['title'], 'ship demo');
    expect((back[1] as Map<Object?, Object?>)['checked'], true);

    component.dispose();
    defs.first.dispose();
    engine.dispose();
  });

  test('invokes callbacks', () async {
    final cwd = Directory.current.path;
    var slintPath = '$cwd/lib/todo.slint';
    if (!File(slintPath).existsSync()) {
      slintPath = '$cwd/example/lib/todo.slint';
    }
    var slintFile = File(slintPath);

    final source = slintFile.readAsStringSync();
    final engine = NativeSlintEngine();
    final defs = await engine.compile(source, path: 'todo.slint');
    final component = defs.first.instantiate() as NativeSlintComponent;

    final received = <Object?>[];
    component.setCallbackHandler('add-todo', (args) {
      received.addAll(args);
      return null;
    });

    component.invokeCallback('add-todo', ['from test']);
    expect(received, ['from test']);

    component.dispose();
    defs.first.dispose();
    engine.dispose();
  });

  test('renders to pixels', () async {
    final cwd = Directory.current.path;
    var slintPath = '$cwd/lib/todo.slint';
    if (!File(slintPath).existsSync()) {
      slintPath = '$cwd/example/lib/todo.slint';
    }
    var slintFile = File(slintPath);

    final source = slintFile.readAsStringSync();
    final engine = NativeSlintEngine();
    final defs = await engine.compile(source, path: 'todo.slint');
    final component = defs.first.instantiate() as NativeSlintComponent;

    final target = component.renderTarget;
    target.resize(400, 600);
    expect(target.render(), isTrue);

    final pixels = target.pixels;
    expect(pixels.length, 400 * 600 * 4);
    expect(pixels.any((b) => b != 0), isTrue, reason: 'frame should have content');

    component.dispose();
    defs.first.dispose();
    engine.dispose();
  });
}

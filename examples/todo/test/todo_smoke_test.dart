import 'dart:io';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:test/test.dart';

/// The raw interpreter API against `ui/todo.slint`, below the generated
/// wrapper: compile, instantiate, model round-trip, callbacks, pixels.
void main() {
  final source = File('ui/todo.slint').readAsStringSync();
  late InterpreterSlintEngine engine;
  late List<InterpreterSlintComponentDefinition> defs;

  setUp(() {
    engine = InterpreterSlintEngine();
    defs = engine.compile(source, path: 'todo.slint');
  });
  tearDown(() {
    for (final d in defs) {
      d.dispose();
    }
    engine.dispose();
  });

  // The compiler hands components back unordered: select by name.
  SlintSoftwareComponent todoApp() =>
      defs.firstWhere((d) => d.name == 'TodoApp').instantiate();

  test('compiles todo.slint', () {
    expect(
      [for (final d in defs) d.name],
      containsAll(['TodoApp', 'UnusedGadget']),
    );
  });

  test('instantiates and syncs model', () {
    final component = todoApp();
    addTearDown(component.dispose);

    component.setProperty('todo-model', [
      {'title': 'buy milk', 'checked': false},
      {'title': 'ship demo', 'checked': true},
    ]);

    final back = component.getProperty('todo-model') as List<Object?>;
    expect(back.length, 2);
    expect((back[0] as Map<Object?, Object?>)['title'], 'buy milk');
    expect((back[0] as Map<Object?, Object?>)['checked'], false);
    expect((back[1] as Map<Object?, Object?>)['title'], 'ship demo');
    expect((back[1] as Map<Object?, Object?>)['checked'], true);
  });

  test('invokes callbacks', () {
    final component = todoApp();
    addTearDown(component.dispose);

    final received = <Object?>[];
    component.setCallbackHandler('add-todo', (args) {
      received.addAll(args);
      return null;
    });

    component.invokeCallback('add-todo', ['from test']);
    expect(received, ['from test']);
  });

  test('renders to pixels', () {
    final component = todoApp();
    addTearDown(component.dispose);

    final target = component.renderTarget;
    target.resize(400, 600);
    expect(target.render(), isTrue);

    final pixels = target.pixels;
    expect(pixels.length, 400 * 600 * 4);
    expect(pixels.any((b) => b != 0), isTrue, reason: 'frame should have content');
  });
}

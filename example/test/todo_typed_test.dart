import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// The generated typed wrapper driven by the interpreter backend: the
/// `.slint` source embedded in `todo.g.dart` is compiled at runtime, so this
/// runs under plain `flutter test` (always debug).
void main() {
  late SlintInterpreterFactory factory;

  setUp(() => factory = SlintInterpreterFactory());
  tearDown(() => factory.dispose());

  test('create() defaults to the interpreter in debug builds', () async {
    // No factory passed: the generated defaultFactory follows the build mode,
    // and `flutter test` is always debug. Do not dispose it — it is shared.
    expect(TodoApp.defaultFactory, isA<SlintInterpreterFactory>());
    final app = await TodoApp.create();
    expect(app.component, isA<InterpreterSlintComponent>());
    app.dispose();
  });

  test('creates TodoApp from the embedded source', () async {
    final app = await TodoApp.create(factory);
    expect(app.component, isA<InterpreterSlintComponent>());
    app.dispose();
  });

  test('todo-model roundtrips through typed accessors', () async {
    final app = await TodoApp.create(factory);

    app.todoModel = [
      {'title': 'buy milk', 'checked': false},
      {'title': 'ship demo', 'checked': true},
    ];

    final back = app.todoModel;
    expect(back.length, 2);
    expect((back[0] as Map<Object?, Object?>)['title'], 'buy milk');
    expect((back[0] as Map<Object?, Object?>)['checked'], false);
    expect((back[1] as Map<Object?, Object?>)['title'], 'ship demo');
    expect((back[1] as Map<Object?, Object?>)['checked'], true);

    app.dispose();
  });

  test('callbacks fire with typed args', () async {
    final app = await TodoApp.create(factory);

    List<Object?>? added;
    List<Object?>? toggled;
    var removedDone = false;
    app.onAddTodo((args) {
      added = args;
      return null;
    });
    app.onToggleTodo((args) {
      toggled = args;
      return null;
    });
    app.onRemoveDone((args) {
      removedDone = true;
      return null;
    });

    app.invokeAddTodo(['write tests']);
    expect(added, ['write tests']);

    app.invokeToggleTodo([1, true]);
    expect(toggled, [1, true]);

    app.invokeRemoveDone();
    expect(removedDone, isTrue);

    app.dispose();
  });

  test('renders to pixels', () async {
    final app = await TodoApp.create(factory);
    final target = app.renderTarget;

    app.todoModel = [
      {'title': 'test todo', 'checked': false},
    ];
    target.resize(400, 300);

    expect(target.render(), isTrue);
    expect(target.pixels.length, 400 * 300 * 4);
    expect(target.pixels.any((b) => b != 0), isTrue,
        reason: 'rendered frame should not be fully transparent black');

    app.dispose();
  });

  test('rejects a component the source does not export', () async {
    expect(
      () => factory.instantiate(TodoApp.slintSource, 'NoSuchComponent'),
      throwsA(isA<StateError>()),
    );
  });
}

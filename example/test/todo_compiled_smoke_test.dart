import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

void main() {
  test('TodoApp creates from embedded source', () async {
    final app = await TodoApp.create();
    expect(app, isNotNull);
    app.dispose();
  });

  test('TodoApp todo-model roundtrip (typed)', () async {
    final app = await TodoApp.create();

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

  test('TodoApp callbacks fire with typed args', () async {
    final app = await TodoApp.create();

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

  test('TodoApp renders to pixels', () async {
    final app = await TodoApp.create();
    final target = app.renderTarget;

    app.todoModel = [
      {'title': 'test todo', 'checked': false},
    ];

    target.resize(400, 300);

    final renderResult = target.render();
    expect(renderResult, isTrue,
        reason: 'First render should succeed. Render returned: $renderResult');

    final pixels = target.pixels;
    expect(pixels.length, 400 * 300 * 4);
    expect(pixels.any((b) => b != 0), isTrue,
        reason: 'Rendered frame should not be fully transparent black');

    app.dispose();
  });
}

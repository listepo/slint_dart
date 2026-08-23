import 'package:slint_compiler/slint_compiler.dart';
import 'package:test/test.dart';

void main() {
  test('CompiledTodoApp constructs', () {
    final app = CompiledTodoApp();
    expect(app, isNotNull);
    app.dispose();
  });

  test('CompiledTodoApp todo-model roundtrip', () {
    final app = CompiledTodoApp();

    final model = [
      {'title': 'buy milk', 'checked': false},
      {'title': 'ship demo', 'checked': true},
    ];
    app.setProperty('todo-model', model);

    final back = app.getProperty('todo-model') as List<Object?>;
    expect(back.length, 2);
    expect((back[0] as Map<Object?, Object?>)['title'], 'buy milk');
    expect((back[0] as Map<Object?, Object?>)['checked'], false);
    expect((back[1] as Map<Object?, Object?>)['title'], 'ship demo');
    expect((back[1] as Map<Object?, Object?>)['checked'], true);

    app.dispose();
  });

  test('CompiledTodoApp callbacks fire with typed args', () {
    final app = CompiledTodoApp();

    List<Object?>? added;
    List<Object?>? toggled;
    var removedDone = false;
    app.setCallbackHandler('add-todo', (args) {
      added = args;
      return null;
    });
    app.setCallbackHandler('toggle-todo', (args) {
      toggled = args;
      return null;
    });
    app.setCallbackHandler('remove-done', (args) {
      removedDone = true;
      return null;
    });

    app.invokeCallback('add-todo', ['write tests']);
    expect(added, ['write tests']);

    app.invokeCallback('toggle-todo', [1, true]);
    expect(toggled, [1, true]);

    app.invokeCallback('remove-done', []);
    expect(removedDone, isTrue);

    app.dispose();
  });

  test('CompiledTodoApp renders to pixels', () {
    final app = CompiledTodoApp();
    final target = app.renderTarget;

    // Initialize model and set initial size
    app.setProperty('todo-model', [
      {'title': 'test todo', 'checked': false},
    ]);

    target.resize(400, 300);

    // Check if render succeeds
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

import 'package:flutter/material.dart';
import 'package:slint_skia/slint_skia.dart';
import 'package:todo_shared/todo_shared.dart';

import 'todo.g.dart';

// The same ui/todo.slint as examples/todo, on the slint_skia backend: the
// Skia engine compiles the source todo.g.dart embeds, the Dart side owns the
// list and pushes it into `todo-model`, and the frame is meant to arrive as a
// Flutter external texture. What the backend does not do yet — render, hand
// out a texture id, deliver callbacks — the page says on screen instead of
// pretending (see packages/slint_skia/README.md, "Shortcuts & Ceilings").

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slint Todo (Skia)',
      theme: ThemeData(useMaterial3: true),
      home: const TodoPage(),
    );
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  SkiaSlintEngine? _engine;
  SkiaSlintComponent? _component;
  SkiaTextureRenderTarget? _target;
  Object? _loadError;

  /// Where the backend stopped short, in the words of its own exceptions.
  final List<String> _ceilings = [];

  // The list itself lives in the shared TodoStore (examples/todo_shared);
  // this page maps it with TodoEntry.toSlint() at the Slint boundary, which
  // matches the generated TodoItem shape.
  final TodoStore _store = TodoStore();

  @override
  void initState() {
    super.initState();
    try {
      final engine = _engine = SkiaSlintEngine();
      // Compiling is one FFI call. The Skia engine hands back the file's
      // root as a single definition (a documented ceiling), so select by
      // name only once it enumerates them.
      final defs = engine.compile(TodoApp.slintSource, path: 'ui/todo.slint');
      final def = defs.length == 1
          ? defs.single
          : defs.firstWhere((d) => d.name == TodoApp.componentName);
      final component = _component = def.instantiate() as SkiaSlintComponent;
      _target = SkiaTextureRenderTarget(component);
      _wire(component);
      _sync();
    } catch (e) {
      _loadError = e;
    }
  }

  void _wire(SkiaSlintComponent component) {
    // Callbacks are not delivered by the Skia backend yet; keep the list
    // Dart-owned and say so rather than silently dropping taps.
    try {
      component.setCallbackHandler('add-todo', (args) {
        _onAddTodo(args.first as String);
        return null;
      });
      component.setCallbackHandler('toggle-todo', (args) {
        _onToggleTodo(args[0] as int, args[1] as bool);
        return null;
      });
      component.setCallbackHandler('remove-done', (_) {
        _onRemoveDone();
        return null;
      });
    } on UnimplementedError catch (e) {
      _ceilings.add('$e');
    }
  }

  void _sync() {
    _component?.setProperty('todo-model', [
      for (final t in _store.items) t.toSlint(),
    ]);
    setState(() {});
  }

  void _onAddTodo(String title) {
    if (_store.addTodo(title)) _sync();
  }

  void _onToggleTodo(int index, bool checked) {
    if (_store.toggleTodo(index, checked)) _sync();
  }

  void _onRemoveDone() {
    _store.removeDone();
    _sync();
  }

  /// The external texture id, or null while the GPU plumbing is stubbed.
  int? _textureId() {
    final target = _target;
    if (target == null) return null;
    try {
      if (!target.render()) {
        _ceiling('render() returned false: no GPU surface bound yet');
        return null;
      }
      return target.textureId;
    } on UnimplementedError catch (e) {
      _ceiling('$e');
      return null;
    }
  }

  void _ceiling(String what) {
    if (!_ceilings.contains(what)) _ceilings.add(what);
  }

  @override
  void dispose() {
    _target?.dispose(); // disposes the component
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textureId = _textureId();
    return Scaffold(
      appBar: AppBar(title: Text(_store.countTitle('SkiaSlintEngine'))),
      body: _loadError != null
          ? Center(child: Text('$_loadError'))
          : textureId != null
          ? Texture(textureId: textureId)
          : _Ceilings(todos: _store.items, ceilings: _ceilings),
    );
  }
}

/// What the app would show if the frame arrived, and why it has not.
class _Ceilings extends StatelessWidget {
  const _Ceilings({required this.todos, required this.ceilings});

  final List<TodoEntry> todos;
  final List<String> ceilings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Compiled and instantiated by the Skia backend; '
          'todo-model synced from Dart:',
        ),
        for (final t in todos)
          ListTile(
            leading: Icon(
              t.checked ? Icons.check_box : Icons.check_box_outline_blank,
            ),
            title: Text(t.title),
          ),
        const Divider(),
        const Text('Not on screen yet — the backend stops here:'),
        for (final c in ceilings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(c, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

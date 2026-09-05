import 'package:flutter/material.dart';
import 'package:slint/slint.dart';

import 'todo.g.dart';

// The app names its UI by the `.slint` path and never a backend:
// `SlintComponent.load('ui/todo.slint')` returns the `TodoApp` registered
// below, built through the generated `defaultFactory`, which follows the
// build mode exactly like the hooks that decide which dylib ships —
// interpreter in debug, AOT in release/profile. Debug compiles the source
// todo.g.dart embeds; release has it compiled into the AOT dylib and carries
// no copy of the text. ui/todo.slint is not a Flutter asset, so the UI source
// stays out of the shipped bundle either way.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Per component, on purpose: UnusedGadget is never registered, so it is
  // tree-shaken out of the release build.
  TodoApp.register();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slint Todo',
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
  TodoApp? _app;
  Object? _loadError;
  // TodoItem is generated from the struct declared in todo.slint.
  final List<TodoItem> _todos = [
    const TodoItem(title: 'Wire Slint into Flutter', checked: true),
    const TodoItem(title: 'Render this list', checked: false),
  ];
  int _openCount = 0;

  @override
  void initState() {
    super.initState();
    // Synchronous in both modes: the interpreter compiles the embedded source
    // in one FFI call, and AOT only creates the instance — so the UI is
    // ready before the first build, with no loading state to render.
    try {
      _app = SlintComponent.load('ui/todo.slint')
        ..onAddTodo(_onAddTodo)
        ..onToggleTodo(_onToggleTodo)
        ..onRemoveDone(_onRemoveDone);
      _sync();
    } catch (e) {
      _loadError = e;
    }
  }

  void _sync() {
    _app!.todoModel = _todos;
    _openCount = _todos.where((t) => !t.checked).length;
    setState(() {});
  }

  void _onAddTodo(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _todos.add(TodoItem(title: trimmed, checked: false));
    _sync();
  }

  void _onToggleTodo(int index, bool checked) {
    if (index < 0 || index >= _todos.length) return;
    _todos[index] = _todos[index].copyWith(checked: checked);
    _sync();
  }

  void _onRemoveDone() {
    _todos.removeWhere((t) => t.checked);
    _sync();
  }

  @override
  void dispose() {
    // The interpreter engine behind TodoApp.defaultFactory is process-wide and
    // shared, so it outlives this widget deliberately.
    _app?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _app?.renderTarget;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_openCount open / ${_todos.length} total'
          ' — ${TodoApp.defaultFactory.runtimeType}',
        ),
      ),
      body: target == null
          ? Center(child: Text('$_loadError'))
          : SlintView(target: target),
    );
  }
}

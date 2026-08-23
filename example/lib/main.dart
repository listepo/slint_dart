import 'package:flutter/material.dart';
import 'package:slint/slint.dart';

import 'todo.g.dart';

// The app never names a backend: `TodoApp.create()` uses the generated
// `defaultFactory`, which follows the build mode exactly like the hooks that
// decide which dylib ships — interpreter in debug, AOT in release/profile.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final List<Map<String, Object?>> _todos = [
    {'title': 'Wire Slint into Flutter', 'checked': true},
    {'title': 'Render this list', 'checked': false},
  ];
  int _openCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final app = await TodoApp.create();
      if (!mounted) {
        app.dispose();
        return;
      }
      _app = app;
      app.onAddTodo(_onAddTodo);
      app.onToggleTodo(_onToggleTodo);
      app.onRemoveDone(_onRemoveDone);
      _sync();
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    }
  }

  void _sync() {
    _app!.todoModel = _todos;
    _openCount = _todos.where((t) => !(t['checked'] as bool? ?? false)).length;
    if (mounted) setState(() {});
  }

  Object? _onAddTodo(List<Object?> args) {
    final title = (args.isNotEmpty ? args[0] : '').toString().trim();
    if (title.isNotEmpty) {
      _todos.add({'title': title, 'checked': false});
      _sync();
    }
    return null;
  }

  Object? _onToggleTodo(List<Object?> args) {
    final index = (args[0] as num).toInt();
    final checked = args[1] as bool;
    if (index >= 0 && index < _todos.length) {
      _todos[index]['checked'] = checked;
      _sync();
    }
    return null;
  }

  Object? _onRemoveDone(List<Object?> args) {
    _todos.removeWhere((t) => t['checked'] as bool? ?? false);
    _sync();
    return null;
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
      body: _loadError != null
          ? Center(child: Text('$_loadError'))
          : target == null
              ? const Center(child: CircularProgressIndicator())
              : SlintView(target: target),
    );
  }
}

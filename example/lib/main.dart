import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';

import 'todo.aot.g.dart' as aot;
import 'todo.g.dart';

/// Backend follows the build mode (mirrors the hooks: debug bundles only the
/// interpreter dylib, release/profile only the AOT dylib). Either way the
/// typed `TodoApp` API generated from `todo.slint` is the same.
const useCompiled = !kDebugMode;

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
  SlintInterpreterFactory? _interpreter;
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
      final SlintComponentFactory factory;
      if (useCompiled) {
        factory = aot.todoAppFactory;
      } else {
        factory = _interpreter = SlintInterpreterFactory();
      }
      final app = await TodoApp.create(factory);
      if (!mounted) {
        app.dispose();
        _interpreter?.dispose();
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
    _app?.dispose();
    _interpreter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _app?.renderTarget;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_openCount open / ${_todos.length} total'
          ' — ${useCompiled ? 'AOT' : 'interpreter'}',
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

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';
import 'todo.g.dart';

/// Backend follows the build mode (mirrors the hooks: debug bundles only the
/// interpreter dylib, release/profile bundle only the AOT dylib).
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
  SlintComponent? _component;
  SlintSoftwareRenderTarget? _target;
  InterpreterSlintEngine? _engine;
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
      if (useCompiled) {
        final app = await TodoApp.create();
        _component = app;
        _target = app.renderTarget;
      } else {
        _engine = InterpreterSlintEngine();
        final source = await rootBundle.loadString('lib/todo.slint');
        final defs = await _engine!.compile(source, path: 'todo.slint');
        try {
          final instance = defs.first.instantiate() as InterpreterSlintComponent;
          _component = instance;
          _target = instance.renderTarget;
        } finally {
          for (final def in defs) {
            def.dispose();
          }
        }
      }
      if (!mounted) {
        _component?.dispose();
        _engine?.dispose();
        return;
      }
      _component!.setCallbackHandler('add-todo', _onAddTodo);
      _component!.setCallbackHandler('toggle-todo', _onToggleTodo);
      _component!.setCallbackHandler('remove-done', _onRemoveDone);
      _sync();
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    }
  }

  void _sync() {
    _component!.setProperty('todo-model', _todos);
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
    _component?.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
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

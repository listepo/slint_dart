import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slint/slint.dart';
import 'package:slint_native/slint_native.dart';
import 'package:slint_compiler/slint_compiler.dart';

const backend = String.fromEnvironment('SLINT_BACKEND', defaultValue: 'interpreter');

DynamicLibrary _openDylib({
  required String envPath,
  required List<String> candidates,
  required String missing,
}) {
  if (envPath.isNotEmpty) {
    return DynamicLibrary.open(envPath);
  }

  final found = candidates
      .map(File.new)
      .where((f) => f.existsSync())
      .map((f) => f.path)
      .toList();

  if (found.isEmpty) {
    throw StateError(missing);
  }

  return DynamicLibrary.open(found.first);
}

DynamicLibrary _openSlintNative() {
  const envPath = String.fromEnvironment('SLINT_NATIVE_LIB');
  return _openDylib(
    envPath: envPath,
    candidates: const [
      'target/debug/libslint_native_ffi.dylib',
      '../target/debug/libslint_native_ffi.dylib',
      'target/debug/libslint_native_ffi.so',
      '../target/debug/libslint_native_ffi.so',
    ],
    missing: 'libslint_native_ffi not found.\n'
        'Build with: cargo build -p slint-native-ffi\n'
        'Or pass: --dart-define=SLINT_NATIVE_LIB=/absolute/path/to/libslint_native_ffi.dylib',
  );
}

DynamicLibrary _openSlintCompiler() {
  const envPath = String.fromEnvironment('SLINT_COMPILER_LIB');
  return _openDylib(
    envPath: envPath,
    candidates: const [
      'target/debug/libslint_compiler_ffi.dylib',
      '../target/debug/libslint_compiler_ffi.dylib',
      'target/debug/libslint_compiler_ffi.so',
      '../target/debug/libslint_compiler_ffi.so',
    ],
    missing: 'libslint_compiler_ffi not found.\n'
        'Build with: cargo build -p slint-compiler-ffi\n'
        'Or pass: --dart-define=SLINT_COMPILER_LIB=/absolute/path/to/libslint_compiler_ffi.dylib',
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (backend == 'interpreter') {
    slintNativeLibraryOverride = _openSlintNative;
  } else if (backend == 'compiled') {
    slintCompilerLibraryOverride = _openSlintCompiler;
  }
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
  NativeSlintEngine? _engine;
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
      if (backend == 'compiled') {
        final app = CompiledTodoApp();
        _component = app;
        _target = app.renderTarget;
      } else {
        _engine = NativeSlintEngine();
        final source = await rootBundle.loadString('todo.slint');
        final defs = await _engine!.compile(source, path: 'todo.slint');
        try {
          final instance = defs.first.instantiate() as NativeSlintComponent;
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
        title: Text('$_openCount open / ${_todos.length} total'),
      ),
      body: _loadError != null
          ? Center(child: Text('$_loadError'))
          : target == null
              ? const Center(child: CircularProgressIndicator())
              : SlintView(target: target),
    );
  }
}

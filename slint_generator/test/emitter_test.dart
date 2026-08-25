import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// Matches generated source by content, ignoring how the formatter wrapped
/// it — the tests are about what is emitted, not where the line breaks fall.
Matcher containsCode(String snippet) => predicate<String>(
      (out) => _flat(out).contains(_flat(snippet)),
      'contains code `$snippet`',
    );

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// A realistic named struct — `slint-introspect` never reports an anonymous
/// one, and never an array without an element type.
final _todoItem = TypeRef('struct', structName: 'TodoItem', fields: [
  PropertySchema('title', TypeRef('string')),
  PropertySchema('checked', TypeRef('bool')),
]);

SlintSchema _schema({
  List<PropertySchema> properties = const [],
  List<CallbackSchema> callbacks = const [],
}) =>
    SlintSchema([ComponentSchema('TodoApp', properties, callbacks)]);

String _wrapper(
  SlintSchema schema, {
  String? aotLibrary,
  bool interpreter = false,
  String? assetPath = 'lib/todo.slint',
  String slintSource = 'export component TodoApp {}',
}) =>
    generateWrapperLibrary(
      schema,
      sourceName: 'todo.slint',
      slintSource: slintSource,
      assetPath: assetPath,
      aotLibrary: aotLibrary,
      interpreter: interpreter,
    );

void main() {
  group('dartStringLiteral', () {
    // The whole .slint source is embedded through this. A miss here produces a
    // generated file that does not parse, or one that silently interpolates.
    test(r'escapes $ so Dart does not interpolate it', () {
      expect(dartStringLiteral(r'cost: $5'), r'"cost: \$5"');
      expect(dartStringLiteral(r'${expr}'), r'"\${expr}"');
    });

    test('escapes quotes and backslashes', () {
      expect(dartStringLiteral('say "hi"'), r'"say \"hi\""');
      expect(dartStringLiteral(r'a\b'), r'"a\\b"');
    });

    test('escapes a backslash followed by a dollar independently', () {
      // Source chars \ then $ must survive as an escaped backslash and an
      // escaped dollar, not as one escape swallowing the other.
      expect(dartStringLiteral(r'\$'), r'"\\\$"');
    });

    test('escapes newlines rather than emitting a multi-line literal', () {
      expect(dartStringLiteral('a\nb'), r'"a\nb"');
    });

    test('wraps the result in quotes', () {
      final out = dartStringLiteral('plain');
      expect(out.startsWith('"'), isTrue);
      expect(out.endsWith('"'), isTrue);
    });
  });

  group('backend defaulting', () {
    test('with neither backend, create requires an explicit factory', () {
      final out = _wrapper(_schema());
      expect(out, containsCode('static Future<TodoApp> create(SlintComponentFactory factory)'));
      expect(out, isNot(containsCode('defaultFactory')));
      expect(out, isNot(containsCode('_useCompiled')));
      expect(out, isNot(containsCode('slint_interpreter')));
      expect(out, isNot(containsCode('aot.')));
    });

    test('with only the interpreter, it is the default', () {
      final out = _wrapper(_schema(), interpreter: true);
      expect(out, containsCode("import 'package:slint_interpreter/slint_interpreter.dart';"));
      expect(out, containsCode('defaultFactory = SlintInterpreterFactory()'));
      expect(out, containsCode('static Future<TodoApp> create([SlintComponentFactory? factory])'));
      expect(out, isNot(containsCode('_useCompiled')));
    });

    test('with only the AOT backend, it is the default', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, containsCode("import 'todo.aot.g.dart' as aot;"));
      expect(out, containsCode('defaultFactory = aot.todoAppFactory'));
      expect(out, isNot(containsCode('_useCompiled')));
      expect(out, isNot(containsCode('SlintInterpreterFactory')));
    });

    test('with both, the default follows the build mode', () {
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(out, containsCode("bool.fromEnvironment('dart.vm.product')"));
      expect(out, containsCode("bool.fromEnvironment('dart.vm.profile')"));
      expect(
        out,
        containsCode('defaultFactory = _useCompiled ? aot.todoAppFactory : SlintInterpreterFactory()'),
      );
    });

    test('loading an asset needs a runtime compiler', () {
      // Interpreter present: an explicit path can be compiled at runtime.
      final interpreted = _wrapper(_schema(), interpreter: true);
      expect(interpreted, containsCode("static const assetPath = 'lib/todo.slint'"));
      expect(interpreted,
          containsCode("import 'package:flutter/services.dart' show rootBundle;"));
      expect(interpreted,
          containsCode('path == null ? _source : await rootBundle.loadString(path)'));

      // AOT only: nothing can be compiled at runtime, so the path is ignored
      // rather than read and thrown away.
      final compiled = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(compiled, containsCode('static Future<TodoApp> load('));
      expect(compiled, isNot(containsCode('rootBundle')));
    });

    test('load never touches the bundle without an explicit path', () {
      // The default has to stay source-only: a wrapper that read `assetPath`
      // on its own would force every app to bundle its `.slint`, which then
      // ships the UI source in release for nothing.
      for (final wrapper in [
        _wrapper(_schema(), interpreter: true),
        _wrapper(_schema(), interpreter: true, aotLibrary: 'todo.aot.g.dart'),
        _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart'),
      ]) {
        expect(wrapper, isNot(containsCode('loadString(path ?? assetPath)')));
        expect(wrapper, isNot(containsCode('loadString(assetPath)')));
      }
    });

    test('with both backends, load follows the build mode like create', () {
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(
        out,
        containsCode(
            'path == null || _useCompiled ? _source : await rootBundle.loadString(path)'),
      );
    });

    test('without a backend there is nothing for load to default to', () {
      final out = _wrapper(_schema());
      expect(out, isNot(containsCode('static Future<TodoApp> load(')));
      expect(out, isNot(containsCode('assetPath')));
    });

    test('the AOT default names the factory slint_compiler generates', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, containsCode('aot.${aotFactoryName('TodoApp')}'));
    });
  });

  group('typed members', () {
    test('maps each supported property kind to a Dart type', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('ratio', TypeRef('float')),
        PropertySchema('count', TypeRef('int')),
        PropertySchema('title', TypeRef('string')),
        PropertySchema('checked', TypeRef('bool')),
        PropertySchema('width', TypeRef('length')),
        PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
        PropertySchema('item', _todoItem),
      ]));

      expect(out, containsCode('double get ratio'));
      expect(out, containsCode('int get count'));
      expect(out, containsCode('String get title'));
      expect(out, containsCode('bool get checked'));
      expect(out, containsCode('double get width'));
      expect(out, containsCode('List<TodoItem> get todoModel'));
      expect(out, containsCode('TodoItem get item'));
    });

    test('converts values in both directions at the boundary', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('count', TypeRef('int')),
        PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
      ]));

      // The bridge speaks JSON: numbers arrive as `num`, structs as maps.
      expect(out, containsCode("(component.getProperty('count') as num).toInt()"));
      expect(
        out,
        containsCode('TodoItem.fromSlint(e as Map<Object?, Object?>)'),
      );
      expect(
        out,
        containsCode("setProperty('todo-model', [for (final e in value) e.toSlint()])"),
      );
    });

    test('casts rather than rebuilds a list that needs no conversion', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('tags', TypeRef('array', element: TypeRef('string'))),
      ]));
      expect(out, containsCode('List<String> get tags'));
      expect(out, containsCode('.cast<String>()'));
      expect(out, containsCode("setProperty('tags', value)"));
    });

    test('accessors keep the kebab-case name on the wire', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
      ]));
      expect(out, containsCode("component.getProperty('todo-model')"));
      expect(out, containsCode("component.setProperty('todo-model',"));
      expect(out, containsCode('set todoModel(List<TodoItem> value)'));
    });

    test('emits a typed on/invoke pair per callback', () {
      final out = _wrapper(_schema(callbacks: [
        CallbackSchema('add-todo', [
          PropertySchema('text', TypeRef('string')),
        ], null),
      ]));
      expect(out, containsCode('void onAddTodo(void Function(String text) handler)'));
      expect(out, containsCode('void invokeAddTodo(String text)'));
      expect(out, containsCode("invokeCallback('add-todo', [text])"));
      // The untyped bridge argument list is unpacked for the handler.
      expect(out, containsCode('handler(arguments[0] as String)'));
    });

    test('names callback arguments positionally when the compiler has no name',
        () {
      final out = _wrapper(_schema(callbacks: [
        CallbackSchema('toggle-todo', [
          PropertySchema('', TypeRef('int')),
          PropertySchema('', TypeRef('bool')),
        ], null),
      ]));
      expect(out, containsCode('void Function(int arg1, bool arg2) handler'));
      expect(out, containsCode('void invokeToggleTodo(int arg1, bool arg2)'));
    });

    test('a callback return value is typed and converted', () {
      final out = _wrapper(_schema(callbacks: [
        CallbackSchema('pick', const [], _todoItem),
      ]));
      expect(out, containsCode('void onPick(TodoItem Function() handler)'));
      expect(out, containsCode('(arguments) => handler().toSlint()'));
      expect(out, containsCode('TodoItem invokePick()'));
      expect(
        out,
        containsCode("TodoItem.fromSlint(component.invokeCallback('pick', []) "
            'as Map<Object?, Object?>'),
      );
    });

    test('rejects a property type the backends cannot marshal', () {
      expect(
        () => _wrapper(_schema(properties: [
          PropertySchema('accent', TypeRef('color')),
        ])),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          containsCode('color'),
        )),
      );
    });
  });

  group('struct classes', () {
    test('emits one class per named struct, deduped across components', () {
      final out = generateWrapperLibrary(
        SlintSchema([
          ComponentSchema('TodoApp',
              [PropertySchema('item', _todoItem)], const []),
          ComponentSchema('SettingsPane',
              [PropertySchema('other', _todoItem)], const []),
        ]),
        sourceName: 'app.slint',
        slintSource: 'x',
      );
      expect('class TodoItem {'.allMatches(out).length, 1);
    });

    test('gives the class a const constructor and typed final fields', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('item', _todoItem),
      ]));
      expect(out, containsCode('const TodoItem({required this.title, '
          'required this.checked});'));
      expect(out, containsCode('final String title;'));
      expect(out, containsCode('final bool checked;'));
    });

    test('roundtrips through the Slint field names, not the Dart ones', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema(
            'item',
            TypeRef('struct', structName: 'Row', fields: [
              PropertySchema('is-done', TypeRef('bool')),
            ])),
      ]));
      expect(out, containsCode('final bool isDone;'));
      expect(out, containsCode("isDone: value['is-done'] as bool"));
      expect(out, containsCode("'is-done': isDone"));
    });

    test('collects structs nested inside other structs', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema(
            'group',
            TypeRef('struct', structName: 'Group', fields: [
              PropertySchema('items', TypeRef('array', element: _todoItem)),
            ])),
      ]));
      expect(out, containsCode('class Group {'));
      expect(out, containsCode('class TodoItem {'));
      expect(out, containsCode('final List<TodoItem> items;'));
    });

    test('compares list fields element-wise, not by identity', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema(
            'group',
            TypeRef('struct', structName: 'Group', fields: [
              PropertySchema('items', TypeRef('array', element: _todoItem)),
            ])),
      ]));
      expect(out, containsCode('bool _eq(Object? a, Object? b)'));
      expect(out, containsCode('_eq(items, other.items)'));
    });

    test('skips the deep helpers when no struct holds a list', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('item', _todoItem),
      ]));
      expect(out, isNot(containsCode('bool _eq(')));
      expect(out, containsCode('title == other.title'));
    });

    test('emits no struct classes for a struct-free component', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('title', TypeRef('string')),
      ]));
      expect(out, isNot(containsCode('fromSlint')));
    });
  });

  test('embeds the source and the component name', () {
    final out = _wrapper(_schema(), slintSource: 'export component TodoApp {}');
    expect(out, containsCode(r'const _source = "export component TodoApp {}"'));
    expect(out, containsCode("static const componentName = 'TodoApp';"));
    expect(out, containsCode('static const slintSource = _source;'));
  });

  test('emits one class per exported component', () {
    final out = generateWrapperLibrary(
      SlintSchema([
        ComponentSchema('TodoApp', const [], const []),
        ComponentSchema('SettingsPane', const [], const []),
      ]),
      sourceName: 'app.slint',
      slintSource: 'x',
    );
    expect(out, containsCode('class TodoApp {'));
    expect(out, containsCode('class SettingsPane {'));
  });
}

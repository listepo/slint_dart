import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

SlintSchema _schema({
  List<PropertySchema> properties = const [],
  List<CallbackSchema> callbacks = const [],
}) =>
    SlintSchema([ComponentSchema('TodoApp', properties, callbacks)]);

String _wrapper(
  SlintSchema schema, {
  String? aotLibrary,
  bool interpreter = false,
  String slintSource = 'export component TodoApp {}',
}) =>
    generateWrapperLibrary(
      schema,
      sourceName: 'todo.slint',
      slintSource: slintSource,
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
      expect(out, contains('static Future<TodoApp> create(SlintComponentFactory factory)'));
      expect(out, isNot(contains('defaultFactory')));
      expect(out, isNot(contains('_useCompiled')));
      expect(out, isNot(contains('slint_interpreter')));
      expect(out, isNot(contains('aot.')));
    });

    test('with only the interpreter, it is the default', () {
      final out = _wrapper(_schema(), interpreter: true);
      expect(out, contains("import 'package:slint_interpreter/slint_interpreter.dart';"));
      expect(out, contains('defaultFactory = SlintInterpreterFactory()'));
      expect(out, contains('static Future<TodoApp> create([SlintComponentFactory? factory])'));
      expect(out, isNot(contains('_useCompiled')));
    });

    test('with only the AOT backend, it is the default', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, contains("import 'todo.aot.g.dart' as aot;"));
      expect(out, contains('defaultFactory = aot.todoAppFactory'));
      expect(out, isNot(contains('_useCompiled')));
      expect(out, isNot(contains('SlintInterpreterFactory')));
    });

    test('with both, the default follows the build mode', () {
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(out, contains("bool.fromEnvironment('dart.vm.product')"));
      expect(out, contains("bool.fromEnvironment('dart.vm.profile')"));
      expect(
        out,
        contains('defaultFactory = _useCompiled ? aot.todoAppFactory : SlintInterpreterFactory()'),
      );
    });

    test('the AOT default names the factory slint_compiler generates', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, contains('aot.${aotFactoryName('TodoApp')}'));
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
        PropertySchema('todo-model', TypeRef('array')),
        PropertySchema('item', TypeRef('struct')),
      ]));

      expect(out, contains('double get ratio'));
      expect(out, contains('int get count'));
      expect(out, contains('String get title'));
      expect(out, contains('bool get checked'));
      expect(out, contains('double get width'));
      expect(out, contains('List<Object?> get todoModel'));
      expect(out, contains('Map<Object?, Object?> get item'));
    });

    test('accessors keep the kebab-case name on the wire', () {
      final out = _wrapper(_schema(properties: [
        PropertySchema('todo-model', TypeRef('array')),
      ]));
      expect(out, contains("component.getProperty('todo-model')"));
      expect(out, contains("component.setProperty('todo-model', value)"));
      expect(out, contains('set todoModel(List<Object?> value)'));
    });

    test('emits an on/invoke pair per callback', () {
      final out = _wrapper(_schema(callbacks: [
        CallbackSchema('add-todo', [TypeRef('string')], null),
      ]));
      expect(out, contains('void onAddTodo(SlintCallbackHandler handler)'));
      expect(out, contains("setCallbackHandler('add-todo', handler)"));
      expect(out, contains('Object? invokeAddTodo('));
      expect(out, contains("invokeCallback('add-todo', arguments)"));
    });

    test('rejects a property type the backends cannot marshal', () {
      expect(
        () => _wrapper(_schema(properties: [
          PropertySchema('accent', TypeRef('color')),
        ])),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('color'),
        )),
      );
    });
  });

  test('embeds the source and the component name', () {
    final out = _wrapper(_schema(), slintSource: 'export component TodoApp {}');
    expect(out, contains(r'const _source = "export component TodoApp {}"'));
    expect(out, contains("static const componentName = 'TodoApp';"));
    expect(out, contains('static const slintSource = _source;'));
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
    expect(out, contains('class TodoApp {'));
    expect(out, contains('class SettingsPane {'));
  });
}

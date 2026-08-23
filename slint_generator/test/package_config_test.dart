import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// The builder decides which backends a wrapper may default to from this. A
/// dev dependency leaking through would generate an import that resolves in
/// tests but breaks the app build, so the regular/dev split is load-bearing.
void main() {
  group('runtimeDependencies', () {
    test('returns the regular dependencies', () {
      final deps = runtimeDependencies('''
name: todo_example
dependencies:
  flutter:
    sdk: flutter
  slint: ^0.1.0
  slint_interpreter: ^0.1.0
''');
      expect(deps, containsAll(['flutter', 'slint', 'slint_interpreter']));
    });

    test('excludes dev_dependencies', () {
      final deps = runtimeDependencies('''
name: todo_example
dependencies:
  slint: ^0.1.0
dev_dependencies:
  slint_compiler: ^0.1.0
  test: ^1.25.0
''');
      expect(deps, contains('slint'));
      expect(deps, isNot(contains('slint_compiler')));
      expect(deps, isNot(contains('test')));
    });

    test('handles a pubspec with no dependencies section', () {
      expect(runtimeDependencies('name: bare\nversion: 1.0.0\n'), isEmpty);
    });

    test('handles an empty dependencies section', () {
      expect(runtimeDependencies('name: bare\ndependencies:\n'), isEmpty);
    });

    test('is not fooled by the word appearing elsewhere', () {
      final deps = runtimeDependencies('''
name: todo_example
description: uses slint_compiler for the AOT path
dependencies:
  slint: ^0.1.0
''');
      expect(deps, isNot(contains('slint_compiler')));
    });
  });
}

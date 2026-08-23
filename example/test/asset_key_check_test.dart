import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lib/todo.slint asset resolves', (tester) async {
    final source = await rootBundle.loadString('lib/todo.slint');
    expect(source, contains('TodoApp'));
  });
}

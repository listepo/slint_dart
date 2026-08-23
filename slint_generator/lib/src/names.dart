/// `todo-model` → `todoModel`.
String camelCase(String kebab) {
  final parts = kebab.split('-').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return kebab;
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

/// `add-todo` → `AddTodo`.
String pascalCase(String kebab) => kebab
    .split('-')
    .where((p) => p.isNotEmpty)
    .map((p) => p[0].toUpperCase() + p.substring(1))
    .join();

/// Slint name → Rust identifier, mirroring i-slint-compiler's `ident()`:
/// dashes become underscores.
String rustIdent(String slintName) => slintName.replaceAll('-', '_');

/// `TodoApp` → `todo_app` (for symbol prefixes and helper fn names).
String snakeFromPascal(String pascal) {
  final b = StringBuffer();
  for (var i = 0; i < pascal.length; i++) {
    final ch = pascal[i];
    final isUpper = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
    if (isUpper && i > 0) b.write('_');
    b.write(ch.toLowerCase());
  }
  return b.toString().replaceAll('-', '_');
}

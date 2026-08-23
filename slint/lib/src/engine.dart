import 'component.dart';

/// Compiles `.slint` source into component definitions.
///
/// Mirrors `slint_interpreter::Compiler`.
abstract interface class SlintEngine {
  /// Compiles [source] and returns the exported component definitions.
  ///
  /// [path] is used for diagnostics and resolving relative imports.
  Future<List<SlintComponentDefinition>> compile(String source, {String? path});

  void dispose();
}

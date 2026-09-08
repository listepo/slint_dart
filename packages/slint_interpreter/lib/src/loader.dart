import 'package:flutter/services.dart' show rootBundle;
import 'package:slint/slint_core.dart';

import 'interpreter_engine.dart';

/// Routes [SlintComponent.loadAsset] through the interpreter, so a `.slint`
/// asset can be compiled and instantiated at runtime.
///
/// Called for you the first time you construct a [SlintInterpreterFactory] —
/// which the generated wrappers do — so an app usually never calls it. Call it
/// explicitly at startup when you use [SlintComponent.loadAsset] on its own.
///
/// Registering twice is harmless: the first backend registered wins, so an
/// application that installed its own loader keeps it.
void useSlintInterpreter() {
  SlintComponent.loader ??= _loadAsset;
}

/// Engine shared by every [SlintComponent.loadAsset]; created on first use so
/// merely importing this package costs nothing.
InterpreterSlintEngine? _engine;

Future<SlintSoftwareComponent> _loadAsset(String path, String? component) async {
  final source = await rootBundle.loadString(path);
  final engine = _engine ??= InterpreterSlintEngine();
  final defs = engine.compile(source, path: path);
  try {
    if (component != null) {
      for (final def in defs) {
        if (def.name == component) return def.instantiate();
      }
      throw StateError(
        "no component named '$component' in '$path' "
        '(found: ${_names(defs)})',
      );
    }
    if (defs.length == 1) return defs.single.instantiate();
    if (defs.isEmpty) throw StateError("'$path' exports no component");
    // Definitions come back unordered, so "the first one" would be a coin
    // flip; make the caller say which.
    throw StateError(
      "'$path' exports ${defs.length} components (${_names(defs)}) — name the "
      'one to load',
    );
  } finally {
    for (final def in defs) {
      def.dispose();
    }
  }
}

String _names(List<SlintComponentDefinition> defs) {
  final names = defs.map((d) => d.name).toList()..sort();
  return names.join(', ');
}

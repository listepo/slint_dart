import 'render_target.dart';

/// A compiled, instantiable component.
///
/// Mirrors `slint_interpreter::ComponentDefinition`.
abstract interface class SlintComponentDefinition {
  String get name;

  SlintComponent instantiate();

  void dispose();
}

typedef SlintCallbackHandler = Object? Function(List<Object?> arguments);

/// A live component instance.
///
/// Mirrors `slint_interpreter::ComponentInstance`. Property and callback
/// values are plain Dart values (bool, num, String — richer types as the
/// backends grow).
abstract interface class SlintComponent {
  Object? getProperty(String name);

  void setProperty(String name, Object? value);

  void setCallbackHandler(String name, SlintCallbackHandler handler);

  Object? invokeCallback(String name, List<Object?> arguments);

  void dispose();
}

/// A live instance that renders through a software target — satisfied by both
/// the interpreter instances (`slint_interpreter`) and the AOT-compiled ones
/// (`slint_compiler`).
abstract interface class SlintSoftwareComponent implements SlintComponent {
  SlintSoftwareRenderTarget get renderTarget;
}

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

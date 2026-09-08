import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.g.dart' as b;
import 'element_info.dart';

/// Thrown when the testing backend rejects an operation — a `.slint` source
/// that does not compile, an unknown property, a stale element.
class SlintTestException implements Exception {
  SlintTestException(this.message);

  final String message;

  @override
  String toString() => 'SlintTestException: $message';
}

/// One recorded invocation of a callback registered with [SlintTestApp.record].
class SlintCall {
  const SlintCall(this.name, this.args);

  final String name;
  final List<Object?> args;

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// An element in the component's accessibility tree.
///
/// An element belongs to the query that produced it. Running another query
/// replaces the snapshot, so acting on an element from an earlier one throws
/// rather than silently acting on whatever now sits at that position — after
/// an interaction, re-run the query.
class SlintElement extends SlintElementInfo {
  SlintElement._(this._app, this._generation, super.json) : super.fromJson();

  final SlintTestApp _app;

  /// The query this element came from; see [SlintTestApp._generation].
  final int _generation;

  int get _index => index;

  /// Invokes the element's accessible default action — pressing a button,
  /// toggling a checkbox.
  void click() {
    _app._checkUsable(this, _generation);
    if (!b.slint_testing_app_click(_app._handle, _index)) {
      throw SlintTestException(_app._lastError() ?? 'click failed on $this');
    }
  }

  /// Sets the element's accessible value — the text of an input, the position
  /// of a slider.
  void setValue(String value) {
    _app._checkUsable(this, _generation);
    final ptr = value.toNativeUtf8();
    try {
      if (!b.slint_testing_app_set_value(_app._handle, _index, ptr.cast())) {
        throw SlintTestException(
            _app._lastError() ?? 'setValue failed on $this');
      }
    } finally {
      calloc.free(ptr);
    }
  }
}

/// A `.slint` component instantiated on Slint's testing backend.
///
/// The component is compiled and instantiated, but never shown or rendered:
/// assertions run against the accessibility tree, so they describe what a
/// user can perceive and do rather than which pixels changed.
///
/// ```dart
/// final app = SlintTestApp.compile(source, component: 'TodoApp');
/// addTearDown(app.dispose);
///
/// app.record('add-todo');
/// app.findById('TodoApp::edit').single.setValue('buy milk');
/// app.findByLabel('Add').single.click();
///
/// expect(app.takeCalls().single.args, ['buy milk']);
/// ```
class SlintTestApp {
  SlintTestApp._(this._handle);

  final b.SlintTestingApp _handle;
  bool _disposed = false;

  /// Bumped every time a query replaces the native element snapshot, so
  /// elements can tell whether the indices they hold still mean anything.
  int _generation = 0;

  /// Compiles [source] and instantiates [component].
  ///
  /// [component] may be omitted when the source exports exactly one — the
  /// compiler returns components unordered, so with several exports there is
  /// no meaningful "first" to fall back on and this throws instead of picking
  /// one arbitrarily.
  ///
  /// [path] is only used to resolve `import` statements and in error
  /// messages.
  factory SlintTestApp.compile(
    String source, {
    String? component,
    String path = 'test.slint',
  }) {
    final sourcePtr = source.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    final componentPtr = component?.toNativeUtf8();
    try {
      final handle = b.slint_testing_app_new(
        sourcePtr.cast(),
        pathPtr.cast(),
        componentPtr?.cast() ?? ffi.nullptr,
      );
      if (handle == ffi.nullptr) {
        throw SlintTestException(
            _readLastError() ?? 'failed to instantiate the component');
      }
      return SlintTestApp._(handle);
    } finally {
      calloc.free(sourcePtr);
      calloc.free(pathPtr);
      if (componentPtr != null) calloc.free(componentPtr);
    }
  }

  /// Every element in the component's accessibility tree.
  List<SlintElement> findAll() => _query('all', null);

  /// Elements whose accessible label is exactly [label] — the user-visible
  /// text of a button, checkbox, or input.
  List<SlintElement> findByLabel(String label) => _query('label', label);

  /// Elements with the given id, qualified by component: `TodoApp::edit`.
  List<SlintElement> findById(String id) => _query('id', id);

  /// Elements of the given type, e.g. `Button` or `CheckBox`.
  List<SlintElement> findByType(String typeName) => _query('type', typeName);

  /// Elements with the given accessible [role], e.g. `Button`, `Checkbox`,
  /// `TextInput`. Filtered client-side from [findAll].
  List<SlintElement> findByRole(String role) =>
      [for (final e in findAll()) if (e.role == role) e];

  List<SlintElement> _query(String kind, String? needle) {
    _checkAlive();
    final kindPtr = kind.toNativeUtf8();
    final needlePtr = needle?.toNativeUtf8();
    try {
      final result = b.slint_testing_app_query(
        _handle,
        kindPtr.cast(),
        needlePtr?.cast() ?? ffi.nullptr,
      );
      final json = _takeString(result) ??
          (throw SlintTestException(_lastError() ?? 'query failed'));
      final generation = ++_generation;
      return [
        for (final e in jsonDecode(json) as List)
          SlintElement._(this, generation, e as Map<String, Object?>),
      ];
    } finally {
      calloc.free(kindPtr);
      if (needlePtr != null) calloc.free(needlePtr);
    }
  }

  /// Reads a property of the component.
  Object? getProperty(String name) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    try {
      final result = b.slint_testing_app_get_property(_handle, namePtr.cast());
      final json = _takeString(result) ??
          (throw SlintTestException(
              _lastError() ?? "failed to read property '$name'"));
      return jsonDecode(json);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Writes a property of the component. [value] is encoded as JSON, so maps
  /// and lists map onto Slint structs and models.
  void setProperty(String name, Object? value) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    final jsonPtr = jsonEncode(value).toNativeUtf8();
    try {
      if (!b.slint_testing_app_set_property(
          _handle, namePtr.cast(), jsonPtr.cast())) {
        throw SlintTestException(
            _lastError() ?? "failed to set property '$name'");
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(jsonPtr);
    }
  }

  /// Invokes a callback or public function on the component and returns its
  /// result.
  Object? invoke(String name, [List<Object?> args = const []]) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    final argsPtr = jsonEncode(args).toNativeUtf8();
    try {
      final result =
          b.slint_testing_app_invoke(_handle, namePtr.cast(), argsPtr.cast());
      final json = _takeString(result) ??
          (throw SlintTestException(
              _lastError() ?? "failed to invoke '$name'"));
      return jsonDecode(json);
    } finally {
      calloc.free(namePtr);
      calloc.free(argsPtr);
    }
  }

  /// Starts recording invocations of the callback [name]; read them back with
  /// [takeCalls]. This replaces any handler the component had for it.
  void record(String name) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    try {
      if (!b.slint_testing_app_record(_handle, namePtr.cast())) {
        throw SlintTestException(
            _lastError() ?? "failed to record callback '$name'");
      }
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Returns the calls recorded since the last drain, and clears the log.
  List<SlintCall> takeCalls() {
    _checkAlive();
    final json = _takeString(b.slint_testing_app_take_calls(_handle)) ??
        (throw SlintTestException(_lastError() ?? 'failed to read calls'));
    return [
      for (final call in jsonDecode(json) as List)
        SlintCall(
          (call as Map<String, Object?>)['name'] as String,
          (call['args'] as List?) ?? const [],
        ),
    ];
  }

  /// Advances the backend's mock clock, driving animations and timers without
  /// waiting in real time.
  void elapse(Duration duration) {
    b.slint_testing_elapse_ms(duration.inMilliseconds);
  }

  /// Releases the component. Safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    b.slint_testing_app_free(_handle);
  }

  void _checkAlive() {
    if (_disposed) {
      throw SlintTestException('this SlintTestApp has been disposed');
    }
  }

  void _checkUsable(SlintElement element, int generation) {
    _checkAlive();
    if (generation != _generation) {
      throw SlintTestException(
          '$element came from an earlier query — re-run the query to act '
          'on it');
    }
  }

  String? _lastError() => _readLastError();

  static String? _readLastError() =>
      _takeString(b.slint_testing_last_error());

  /// Decodes an owned C string and frees it; null stays null.
  static String? _takeString(ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return null;
    final s = ptr.cast<Utf8>().toDartString();
    b.slint_testing_string_free(ptr);
    return s;
  }
}

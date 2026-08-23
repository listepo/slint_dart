import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:slint/slint.dart';

import 'bindings.g.dart';
import 'library.dart';

final _bindings = SlintCompilerBindings(openSlintCompilerLibrary());

String _getLastError() {
  final errorCStr = _bindings.slint_compiler_last_error();
  if (errorCStr.address == 0) {
    return 'Unknown error';
  }
  final error = errorCStr.cast<Utf8>().toDartString();
  _bindings.slint_compiler_string_free(errorCStr.cast());
  return error;
}

class _CompiledTodoSoftwareRenderTarget implements SlintSoftwareRenderTarget {
  final CompiledTodoApp _app;
  Pointer<Uint8> _pixelBuffer = nullptr;
  Uint8List _pixels = Uint8List(0);

  _CompiledTodoSoftwareRenderTarget(this._app);

  @override
  SlintComponent get component => _app;

  @override
  int get width => _app._width;

  @override
  int get height => _app._height;

  @override
  void resize(int width, int height) {
    if (width == _app._width && height == _app._height) {
      return;
    }
    _app._width = width;
    _app._height = height;
    if (_pixelBuffer.address != 0) {
      malloc.free(_pixelBuffer);
    }
    final bufferSize = width * height * 4;
    _pixelBuffer = malloc<Uint8>(bufferSize);
    _pixels = _pixelBuffer.asTypedList(bufferSize);
    _bindings.slint_compiler_todo_set_size(_app._handle, width, height);
  }

  @override
  bool render() {
    if (_pixelBuffer.address == 0) {
      return false;
    }
    return _bindings.slint_compiler_todo_render(
      _app._handle,
      _pixelBuffer,
      _pixels.lengthInBytes,
    );
  }

  @override
  Uint8List get pixels => _pixels;

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    _bindings.slint_compiler_todo_pointer_event(
      _app._handle,
      event.kind.index,
      event.x,
      event.y,
      event.button.index,
      event.scrollDeltaX,
      event.scrollDeltaY,
    );
  }

  @override
  void dispatchKeyEvent(SlintKeyEvent event) {
    final textCStr = event.text.toNativeUtf8();
    try {
      _bindings.slint_compiler_todo_key_event(
        _app._handle,
        textCStr.cast(),
        event.pressed,
      );
    } finally {
      malloc.free(textCStr);
    }
  }

  @override
  void dispose() {
    if (_pixelBuffer.address != 0) {
      malloc.free(_pixelBuffer);
      _pixelBuffer = nullptr;
      _pixels = Uint8List(0);
    }
  }
}

/// A compiled Slint TodoApp component (no interpreter).
///
/// Constructed via the typed FFI surface exported by slint-compiler-ffi.
/// The component is instantiated at creation time; all callbacks and data
/// mutations flow through the bridge.
class CompiledTodoApp implements SlintComponent {
  final Pointer<Void> _handle;
  late final _CompiledTodoSoftwareRenderTarget _renderTarget =
      _CompiledTodoSoftwareRenderTarget(this);
  final Map<String, NativeCallable<Function>> _callbacks = {};
  int _width = 0;
  int _height = 0;

  /// Create a new CompiledTodoApp instance.
  ///
  /// Throws [StateError] if the FFI call fails.
  CompiledTodoApp()
      : _handle = _bindings.slint_compiler_todo_new() {
    if (_handle.address == 0) {
      throw StateError('Failed to create TodoApp: ${_getLastError()}');
    }
  }

  /// Lazily-created software render target sharing the same instance handle.
  SlintSoftwareRenderTarget get renderTarget => _renderTarget;

  @override
  Object? getProperty(String name) {
    // Only "todo-model" is supported in the compiled path
    if (name != 'todo-model') {
      throw ArgumentError('CompiledTodoApp has no property "$name"');
    }

    final jsonCStr = _bindings.slint_compiler_todo_get_model(_handle);
    if (jsonCStr.address == 0) {
      throw StateError(_getLastError());
    }
    final json = jsonCStr.cast<Utf8>().toDartString();
    _bindings.slint_compiler_string_free(jsonCStr.cast());
    return jsonDecode(json);
  }

  @override
  void setProperty(String name, Object? value) {
    // Only "todo-model" is supported in the compiled path
    if (name != 'todo-model') {
      throw ArgumentError('CompiledTodoApp has no property "$name"');
    }

    final jsonStr = jsonEncode(value);
    final jsonCStr = jsonStr.toNativeUtf8();

    try {
      final success = _bindings.slint_compiler_todo_set_model(_handle, jsonCStr.cast());
      if (!success) {
        throw StateError(_getLastError());
      }
    } finally {
      malloc.free(jsonCStr);
    }
  }

  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    // Register the new trampoline with rust first, then close the old one.
    final NativeCallable<Function> callable;
    final bool registered;
    switch (name) {
      case 'add-todo':
        final c =
            NativeCallable<slint_compiler_callback_add_todoFunction>.isolateLocal(
          (Pointer<Void> userData, Pointer<Char> text) {
            // Copy the string before Rust frees it
            handler([text.cast<Utf8>().toDartString()]);
          },
        );
        callable = c;
        registered = _bindings.slint_compiler_todo_on_add_todo(
            _handle, c.nativeFunction, nullptr);
      case 'toggle-todo':
        final c = NativeCallable<
            slint_compiler_callback_toggle_todoFunction>.isolateLocal(
          (Pointer<Void> userData, int index, bool checked) {
            handler([index, checked]);
          },
        );
        callable = c;
        registered = _bindings.slint_compiler_todo_on_toggle_todo(
            _handle, c.nativeFunction, nullptr);
      case 'remove-done':
        final c = NativeCallable<
            slint_compiler_callback_remove_doneFunction>.isolateLocal(
          (Pointer<Void> userData) {
            handler(const []);
          },
        );
        callable = c;
        registered = _bindings.slint_compiler_todo_on_remove_done(
            _handle, c.nativeFunction, nullptr);
      default:
        throw ArgumentError('CompiledTodoApp has no callback "$name"');
    }

    if (!registered) {
      callable.close();
      throw StateError(_getLastError());
    }
    _callbacks.remove(name)?.close();
    _callbacks[name] = callable;
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    final bool ok;
    switch (name) {
      case 'add-todo':
        final textCStr = (arguments[0] as String).toNativeUtf8();
        try {
          ok = _bindings.slint_compiler_todo_invoke_add_todo(
              _handle, textCStr.cast());
        } finally {
          malloc.free(textCStr);
        }
      case 'toggle-todo':
        ok = _bindings.slint_compiler_todo_invoke_toggle_todo(
            _handle, arguments[0] as int, arguments[1] as bool);
      case 'remove-done':
        ok = _bindings.slint_compiler_todo_invoke_remove_done(_handle);
      default:
        throw ArgumentError('CompiledTodoApp has no callback "$name"');
    }
    if (!ok) {
      throw StateError(_getLastError());
    }
    // Callbacks return void on the compiled path.
    return null;
  }

  @override
  void dispose() {
    _bindings.slint_compiler_todo_free(_handle);
    for (final callable in _callbacks.values) {
      callable.close();
    }
    _callbacks.clear();
    _renderTarget.dispose();
  }
}

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:slint/slint_core.dart';

import 'bindings.g.dart';

typedef _NativeSlintCallbackFn = Void Function(Pointer<Void>, Pointer<Char>);

class _NativeDefList {
  _NativeDefList(this.handle);

  final SlintNativeDefinitionList handle;
  int _refs = 0;
  bool _freed = false;

  void retain() => _refs++;

  void release() {
    _refs--;
    if (_refs <= 0 && !_freed) {
      _freed = true;
      slint_native_definitions_free(handle);
    }
  }
}

class NativeSlintEngine implements SlintEngine {
  late final _handle = slint_native_engine_new();

  @override
  Future<List<SlintComponentDefinition>> compile(String source, {String? path}) async {
    final sourceCStr = source.toNativeUtf8();
    final pathCStr = path?.toNativeUtf8() ?? nullptr;

    try {
      final defList = slint_native_engine_compile(
        _handle,
        sourceCStr.cast(),
        pathCStr.cast(),
      );

      if (defList.address == 0) {
        throw StateError(_getLastError());
      }

      final count = slint_native_definitions_count(defList);
      if (count == 0) {
        slint_native_definitions_free(defList);
        return const [];
      }

      final owner = _NativeDefList(defList);
      return [
        for (var i = 0; i < count; i++) NativeSlintComponentDefinition._(owner, i),
      ];
    } finally {
      malloc.free(sourceCStr);
      if (pathCStr.address != 0) {
        malloc.free(pathCStr);
      }
    }
  }

  @override
  void dispose() {
    slint_native_engine_free(_handle);
  }
}

class NativeSlintComponentDefinition implements SlintComponentDefinition {
  final _NativeDefList _list;
  final int _index;
  bool _disposed = false;
  late final String _cachedName = () {
    final nameCStr = slint_native_definitions_name(_list.handle, _index);
    if (nameCStr.address == 0) {
      throw StateError(_getLastError());
    }
    final name = nameCStr.cast<Utf8>().toDartString();
    slint_native_string_free(nameCStr.cast());
    return name;
  }();

  NativeSlintComponentDefinition._(this._list, this._index) {
    _list.retain();
  }

  @override
  String get name => _cachedName;

  String _jsonString(
    Pointer<Char> Function(SlintNativeDefinitionList, int) fn,
  ) {
    if (_disposed) {
      throw StateError('Component definition is disposed');
    }
    final cStr = fn(_list.handle, _index);
    if (cStr.address == 0) {
      throw StateError(_getLastError());
    }
    final json = cStr.cast<Utf8>().toDartString();
    slint_native_string_free(cStr.cast());
    return json;
  }

  /// Public properties: name → Slint value type
  /// (Number, String, Bool, Model, Struct, Brush, Image, Void, ...).
  Map<String, String> properties() {
    final parsed =
        jsonDecode(_jsonString(slint_native_definitions_properties_json))
            as List<Object?>;
    return {
      for (final e in parsed.cast<Map<String, Object?>>())
        e['name'] as String: e['type'] as String,
    };
  }

  /// Public callback names.
  List<String> callbacks() {
    final parsed =
        jsonDecode(_jsonString(slint_native_definitions_callbacks_json))
            as List<Object?>;
    return parsed.cast<String>();
  }

  @override
  NativeSlintComponent instantiate() {
    if (_disposed) {
      throw StateError('Component definition is disposed');
    }
    final instHandle = slint_native_instantiate(_list.handle, _index);
    if (instHandle.address == 0) {
      throw StateError(_getLastError());
    }
    return NativeSlintComponent(instHandle);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _list.release();
  }
}

class NativeSlintComponent implements SlintComponent {
  final SlintNativeInstance _instanceHandle;
  late final NativeSoftwareRenderTarget _renderTarget = NativeSoftwareRenderTarget(this);
  final Map<String, NativeCallable<_NativeSlintCallbackFn>> _callbacks = {};
  bool _disposed = false;

  NativeSlintComponent(this._instanceHandle);

  /// Lazily-created software render target sharing the same instance handle.
  NativeSoftwareRenderTarget get renderTarget => _renderTarget;

  @override
  Object? getProperty(String name) {
    final nameCStr = name.toNativeUtf8();
    try {
      final jsonCStr = slint_native_instance_get_property(_instanceHandle, nameCStr.cast());
      if (jsonCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final json = jsonCStr.cast<Utf8>().toDartString();
      slint_native_string_free(jsonCStr.cast());
      return _jsonToValue(json);
    } finally {
      malloc.free(nameCStr);
    }
  }

  @override
  void setProperty(String name, Object? value) {
    final nameCStr = name.toNativeUtf8();
    final jsonStr = _valueToJson(value);
    final jsonCStr = jsonStr.toNativeUtf8();

    try {
      final success = slint_native_instance_set_property(
        _instanceHandle,
        nameCStr.cast(),
        jsonCStr.cast(),
      );
      if (!success) {
        throw StateError(_getLastError());
      }
    } finally {
      malloc.free(nameCStr);
      malloc.free(jsonCStr);
    }
  }

  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    // Create the trampoline first; only close the old one after rust has
    // the new pointer, so a failed set_callback cannot leave a dangling fn.
    final callable = NativeCallable<_NativeSlintCallbackFn>.isolateLocal(
      (Pointer<Void> userData, Pointer<Char> argsJsonPtr) {
        final argsJson = argsJsonPtr.cast<Utf8>().toDartString();
        try {
          final args = jsonDecode(argsJson) as List<dynamic>;
          // ponytail: handler return values ignored; Slint side gets Void
          handler(args);
        } catch (_) {
          // Silently ignore parsing errors
        }
      },
    );

    final nameCStr = name.toNativeUtf8();
    try {
      final success = slint_native_instance_set_callback(
        _instanceHandle,
        nameCStr.cast(),
        callable.nativeFunction,
        nullptr,
      );
      if (!success) {
        callable.close();
        throw StateError(_getLastError());
      }
    } finally {
      malloc.free(nameCStr);
    }

    _callbacks.remove(name)?.close();
    _callbacks[name] = callable;
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    final nameCStr = name.toNativeUtf8();
    final argsJson = jsonEncode(arguments);
    final argsCStr = argsJson.toNativeUtf8();

    try {
      final resultCStr = slint_native_instance_invoke(
        _instanceHandle,
        nameCStr.cast(),
        argsCStr.cast(),
      );
      if (resultCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final resultJson = resultCStr.cast<Utf8>().toDartString();
      slint_native_string_free(resultCStr.cast());
      return _jsonToValue(resultJson);
    } finally {
      malloc.free(nameCStr);
      malloc.free(argsCStr);
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    slint_native_instance_free(_instanceHandle);
    for (final callable in _callbacks.values) {
      callable.close();
    }
    _callbacks.clear();
    _renderTarget.dispose();
  }
}

class NativeSoftwareRenderTarget implements SlintSoftwareRenderTarget {
  final NativeSlintComponent _component;
  Pointer<Uint8> _pixelBuffer = nullptr;
  Uint8List _pixels = Uint8List(0);
  int _width = 800;
  int _height = 600;
  bool _disposed = false;

  NativeSoftwareRenderTarget(this._component) {
    _allocateBuffer();
  }

  void _allocateBuffer() {
    final bufferSize = _width * _height * 4;
    _pixelBuffer = malloc<Uint8>(bufferSize);
    _pixels = _pixelBuffer.asTypedList(bufferSize);
  }

  @override
  SlintComponent get component => _component;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  void resize(int width, int height) {
    if (_disposed || (width == _width && height == _height)) {
      return;
    }
    if (_pixelBuffer.address != 0) {
      malloc.free(_pixelBuffer);
      _pixelBuffer = nullptr;
    }
    _width = width;
    _height = height;
    _allocateBuffer();
    slint_native_instance_set_size(_component._instanceHandle, width, height);
  }

  @override
  bool render() {
    if (_disposed || _pixelBuffer.address == 0) {
      return false;
    }
    return slint_native_instance_render(
      _component._instanceHandle,
      _pixelBuffer.cast(),
      _pixels.length,
    );
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    slint_native_instance_pointer_event(
      _component._instanceHandle,
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
      slint_native_instance_key_event(
        _component._instanceHandle,
        textCStr.cast(),
        event.pressed,
      );
    } finally {
      malloc.free(textCStr);
    }
  }

  @override
  Uint8List get pixels => _pixels;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_pixelBuffer.address != 0) {
      malloc.free(_pixelBuffer);
      _pixelBuffer = nullptr;
      _pixels = Uint8List(0);
    }
  }
}

String _getLastError() {
  final errCStr = slint_native_last_error();
  if (errCStr.address == 0) {
    return 'unknown error';
  }
  final err = errCStr.cast<Utf8>().toDartString();
  slint_native_string_free(errCStr.cast());
  return err;
}

String _valueToJson(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    return value.toString();
  }
  if (value is String) {
    return jsonEncode(value);
  }
  return jsonEncode(value);
}

Object? _jsonToValue(String json) {
  if (json == 'null') {
    return null;
  }
  try {
    final decoded = jsonDecode(json);
    return decoded;
  } catch (_) {
    return json;
  }
}

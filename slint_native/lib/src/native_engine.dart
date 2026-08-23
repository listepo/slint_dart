import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:slint/slint.dart';

import 'bindings.g.dart';
import 'library.dart';

late final _bindings = SlintNativeBindings(openSlintNativeLibrary());

class NativeSlintEngine implements SlintEngine {
  late final _handle = _bindings.slint_native_engine_new();

  @override
  Future<List<SlintComponentDefinition>> compile(String source, {String? path}) async {
    final sourceCStr = source.toNativeUtf8();
    final pathCStr = path?.toNativeUtf8() ?? nullptr;

    try {
      final defList = _bindings.slint_native_engine_compile(
        _handle,
        sourceCStr.cast(),
        pathCStr.cast(),
      );

      if (defList.address == 0) {
        throw StateError(_getLastError());
      }

      final count = _bindings.slint_native_definitions_count(defList);
      final defs = <SlintComponentDefinition>[];

      for (var i = 0; i < count; i++) {
        final nameCStr = _bindings.slint_native_definitions_name(defList, i);
        if (nameCStr.address == 0) {
          throw StateError(_getLastError());
        }
        final name = nameCStr.cast<Utf8>().toDartString();
        _bindings.slint_native_string_free(nameCStr.cast());

        defs.add(NativeSlintComponentDefinition(this, defList, i));
      }

      return defs;
    } finally {
      malloc.free(sourceCStr);
      if (pathCStr.address != 0) {
        malloc.free(pathCStr);
      }
    }
  }

  @override
  void dispose() {
    _bindings.slint_native_engine_free(_handle);
  }
}

class NativeSlintComponentDefinition implements SlintComponentDefinition {
  final NativeSlintEngine _engine;
  final _defListHandle;
  final int _index;
  late final String _cachedName = () {
    final nameCStr = _bindings.slint_native_definitions_name(_defListHandle, _index);
    if (nameCStr.address == 0) {
      throw StateError(_getLastError());
    }
    final name = nameCStr.cast<Utf8>().toDartString();
    _bindings.slint_native_string_free(nameCStr.cast());
    return name;
  }();

  NativeSlintComponentDefinition(this._engine, this._defListHandle, this._index);

  @override
  String get name => _cachedName;

  @override
  NativeSlintComponent instantiate() {
    final instHandle = _bindings.slint_native_instantiate(_defListHandle, _index);
    if (instHandle.address == 0) {
      throw StateError(_getLastError());
    }
    return NativeSlintComponent(instHandle);
  }

  @override
  void dispose() {
    // definitions list is freed after all defs retrieved
  }
}

class NativeSlintComponent implements SlintComponent {
  final _instanceHandle;
  late final NativeSoftwareRenderTarget _renderTarget = NativeSoftwareRenderTarget(this);

  NativeSlintComponent(this._instanceHandle);

  /// Lazily-created software render target sharing the same instance handle.
  NativeSoftwareRenderTarget get renderTarget => _renderTarget;

  @override
  Object? getProperty(String name) {
    final nameCStr = name.toNativeUtf8();
    try {
      final jsonCStr = _bindings.slint_native_instance_get_property(_instanceHandle, nameCStr.cast());
      if (jsonCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final json = jsonCStr.cast<Utf8>().toDartString();
      _bindings.slint_native_string_free(jsonCStr.cast());
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
      final success = _bindings.slint_native_instance_set_property(
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
    throw UnimplementedError('Rust→Dart callbacks: wire via NativeCallable');
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    final nameCStr = name.toNativeUtf8();
    final argsJson = jsonEncode(arguments);
    final argsCStr = argsJson.toNativeUtf8();

    try {
      final resultCStr = _bindings.slint_native_instance_invoke(
        _instanceHandle,
        nameCStr.cast(),
        argsCStr.cast(),
      );
      if (resultCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final resultJson = resultCStr.cast<Utf8>().toDartString();
      _bindings.slint_native_string_free(resultCStr.cast());
      return _jsonToValue(resultJson);
    } finally {
      malloc.free(nameCStr);
      malloc.free(argsCStr);
    }
  }

  @override
  void dispose() {
    _renderTarget.dispose();
    _bindings.slint_native_instance_free(_instanceHandle);
  }
}

class NativeSoftwareRenderTarget implements SlintSoftwareRenderTarget {
  final NativeSlintComponent _component;
  late Pointer<Uint8> _pixelBuffer;
  late Uint8List _pixels;
  int _width = 800;
  int _height = 600;

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
    if (width == _width && height == _height) {
      return;
    }
    malloc.free(_pixelBuffer);
    _width = width;
    _height = height;
    _allocateBuffer();
    _bindings.slint_native_instance_set_size(_component._instanceHandle, width, height);
  }

  @override
  bool render() {
    return _bindings.slint_native_instance_render(
      _component._instanceHandle,
      _pixelBuffer.cast(),
      _pixels.length,
    );
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    _bindings.slint_native_instance_pointer_event(
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
      _bindings.slint_native_instance_key_event(
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
    malloc.free(_pixelBuffer);
  }
}

String _getLastError() {
  final errCStr = _bindings.slint_native_last_error();
  if (errCStr.address == 0) {
    return 'unknown error';
  }
  final err = errCStr.cast<Utf8>().toDartString();
  _bindings.slint_native_string_free(errCStr.cast());
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

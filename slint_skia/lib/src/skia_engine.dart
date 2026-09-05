import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:slint/slint.dart';
import 'library.dart';

// Define C function signatures
typedef SlintSkiaEngineNewNative = Pointer<Void> Function();
typedef SlintSkiaEngineNew = Pointer<Void> Function();

typedef SlintSkiaEngineCompileNative = Pointer<Void> Function(
  Pointer<Void> engine,
  Pointer<Char> source,
  Pointer<Char> path,
);
typedef SlintSkiaEngineCompile = Pointer<Void> Function(
  Pointer<Void> engine,
  Pointer<Char> source,
  Pointer<Char> path,
);

typedef SlintSkiaEngineFreeeNative = Void Function(Pointer<Void> engine);
typedef SlintSkiaEngineFree = void Function(Pointer<Void> engine);

typedef SlintSkiaInstantiateNative = Pointer<Void> Function(
  Pointer<Void> definition,
);
typedef SlintSkiaInstantiate = Pointer<Void> Function(
  Pointer<Void> definition,
);

typedef SlintSkiaInstanceFreeNative = Void Function(Pointer<Void> instance);
typedef SlintSkiaInstanceFree = void Function(Pointer<Void> instance);

typedef SlintSkiaInstanceSetSizeNative = Bool Function(
  Pointer<Void> instance,
  Float width,
  Float height,
);
typedef SlintSkiaInstanceSetSize = bool Function(
  Pointer<Void> instance,
  double width,
  double height,
);

typedef SlintSkiaInstanceRenderNative = Bool Function(Pointer<Void> instance);
typedef SlintSkiaInstanceRender = bool Function(Pointer<Void> instance);

typedef SlintSkiaInstanceTextureIdNative = Int64 Function(
  Pointer<Void> instance,
);
typedef SlintSkiaInstanceTextureId = int Function(Pointer<Void> instance);

typedef SlintSkiaInstanceGetPropertyNative = Pointer<Char> Function(
  Pointer<Void> instance,
  Pointer<Char> name,
);
typedef SlintSkiaInstanceGetProperty = Pointer<Char> Function(
  Pointer<Void> instance,
  Pointer<Char> name,
);

typedef SlintSkiaInstanceSetPropertyNative = Bool Function(
  Pointer<Void> instance,
  Pointer<Char> name,
  Pointer<Char> valueJson,
);
typedef SlintSkiaInstanceSetProperty = bool Function(
  Pointer<Void> instance,
  Pointer<Char> name,
  Pointer<Char> valueJson,
);

typedef SlintSkiaInstanceInvokeNative = Pointer<Char> Function(
  Pointer<Void> instance,
  Pointer<Char> name,
  Pointer<Char> argsJson,
);
typedef SlintSkiaInstanceInvoke = Pointer<Char> Function(
  Pointer<Void> instance,
  Pointer<Char> name,
  Pointer<Char> argsJson,
);

typedef SlintSkiaLastErrorNative = Pointer<Char> Function();
typedef SlintSkiaLastError = Pointer<Char> Function();

typedef SlintSkiaStringFreeNative = Void Function(Pointer<Char> ptr);
typedef SlintSkiaStringFree = void Function(Pointer<Char> ptr);

// Bind functions
final _engineNew = skiaLib
    .lookup<NativeFunction<SlintSkiaEngineNewNative>>('slint_skia_engine_new')
    .asFunction<SlintSkiaEngineNew>();

final _engineCompile = skiaLib
    .lookup<NativeFunction<SlintSkiaEngineCompileNative>>(
        'slint_skia_engine_compile')
    .asFunction<SlintSkiaEngineCompile>();

final _engineFree = skiaLib
    .lookup<NativeFunction<SlintSkiaEngineFreeeNative>>('slint_skia_engine_free')
    .asFunction<SlintSkiaEngineFree>();

final _instantiate = skiaLib
    .lookup<NativeFunction<SlintSkiaInstantiateNative>>(
        'slint_skia_instantiate')
    .asFunction<SlintSkiaInstantiate>();

final _instanceFree = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceFreeNative>>(
        'slint_skia_instance_free')
    .asFunction<SlintSkiaInstanceFree>();

final _instanceSetSize = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceSetSizeNative>>(
        'slint_skia_instance_set_size')
    .asFunction<SlintSkiaInstanceSetSize>();

final _instanceRender = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceRenderNative>>(
        'slint_skia_instance_render')
    .asFunction<SlintSkiaInstanceRender>();

final _instanceTextureId = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceTextureIdNative>>(
        'slint_skia_instance_texture_id')
    .asFunction<SlintSkiaInstanceTextureId>();

final _instanceGetProperty = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceGetPropertyNative>>(
        'slint_skia_instance_get_property')
    .asFunction<SlintSkiaInstanceGetProperty>();

final _instanceSetProperty = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceSetPropertyNative>>(
        'slint_skia_instance_set_property')
    .asFunction<SlintSkiaInstanceSetProperty>();

final _instanceInvoke = skiaLib
    .lookup<NativeFunction<SlintSkiaInstanceInvokeNative>>(
        'slint_skia_instance_invoke')
    .asFunction<SlintSkiaInstanceInvoke>();

final _lastError = skiaLib
    .lookup<NativeFunction<SlintSkiaLastErrorNative>>(
        'slint_skia_last_error')
    .asFunction<SlintSkiaLastError>();

final _stringFree = skiaLib
    .lookup<NativeFunction<SlintSkiaStringFreeNative>>(
        'slint_skia_string_free')
    .asFunction<SlintSkiaStringFree>();

// Utility to read Rust error
String _getLastError() {
  final ptr = _lastError();
  if (ptr == nullptr) {
    return 'Unknown error';
  }
  final msg = ptr.cast<Utf8>().toDartString();
  return msg;
}

// Utility to free C strings
void _freeString(Pointer<Char> ptr) {
  if (ptr != nullptr) {
    _stringFree(ptr);
  }
}

/// Implementation of SlintEngine using Skia renderer
class SkiaSlintEngine implements SlintEngine {
  late Pointer<Void> _enginePtr;

  SkiaSlintEngine() {
    _enginePtr = _engineNew();
    if (_enginePtr == nullptr) {
      throw StateError('Failed to create Skia engine: ${_getLastError()}');
    }
  }

  @override
  List<SlintComponentDefinition> compile(
    String source, {
    String? path,
  }) {
    final sourceCString = source.toNativeUtf8();
    final pathCString = (path ?? '').toNativeUtf8();

    try {
      final defPtr = _engineCompile(
        _enginePtr,
        sourceCString.cast<Char>(),
        pathCString.cast<Char>(),
      );

      if (defPtr == nullptr) {
        throw StateError(
          'Failed to compile: ${_getLastError()}',
        );
      }

      return [
        SkiaSlintComponentDefinition._create(defPtr, 'SkiaComponent'),
      ];
    } finally {
      calloc.free(sourceCString);
      calloc.free(pathCString);
    }
  }

  @override
  void dispose() {
    if (_enginePtr != nullptr) {
      _engineFree(_enginePtr);
      _enginePtr = nullptr;
    }
  }
}

/// Implementation of SlintComponentDefinition for Skia
class SkiaSlintComponentDefinition implements SlintComponentDefinition {
  late Pointer<Void> _defPtr;
  final String _name;

  SkiaSlintComponentDefinition._create(this._defPtr, this._name);

  @override
  String get name => _name;

  /// Instantiate this component definition
  @override
  SlintComponent instantiate() {
    final instPtr = _instantiate(_defPtr);
    if (instPtr == nullptr) {
      throw StateError(
        'Failed to instantiate: ${_getLastError()}',
      );
    }
    return SkiaSlintComponent._create(instPtr);
  }

  @override
  void dispose() {
    // Component definition disposal not yet implemented
  }
}

/// Implementation of SlintComponent for Skia
class SkiaSlintComponent implements SlintComponent {
  late Pointer<Void> _instPtr;

  SkiaSlintComponent._create(this._instPtr);

  /// Set the component size in logical pixels
  void setSize(double width, double height) {
    final success = _instanceSetSize(_instPtr, width, height);
    if (!success) {
      throw StateError(
        'Failed to set size: ${_getLastError()}',
      );
    }
  }

  /// Get a property value as JSON
  @override
  Object? getProperty(String name) {
    final nameCString = name.toNativeUtf8();
    try {
      final jsonPtr = _instanceGetProperty(_instPtr, nameCString.cast<Char>());
      if (jsonPtr == nullptr) {
        throw StateError(
          'Failed to get property "$name": ${_getLastError()}',
        );
      }
      final jsonStr = jsonPtr.cast<Utf8>().toDartString();
      _freeString(jsonPtr);
      return jsonDecode(jsonStr);
    } finally {
      calloc.free(nameCString);
    }
  }

  /// Set a property value from JSON
  @override
  void setProperty(String name, Object? value) {
    final nameCString = name.toNativeUtf8();
    final valueJson = jsonEncode(value);
    final jsonCString = valueJson.toNativeUtf8();

    try {
      final success = _instanceSetProperty(
        _instPtr,
        nameCString.cast<Char>(),
        jsonCString.cast<Char>(),
      );
      if (!success) {
        throw StateError(
          'Failed to set property "$name": ${_getLastError()}',
        );
      }
    } finally {
      calloc.free(nameCString);
      calloc.free(jsonCString);
    }
  }

  /// Invoke a callback with arguments
  dynamic invoke(String name, List<dynamic> args) {
    final nameCString = name.toNativeUtf8();
    final argsJson = jsonEncode(args);
    final argsCString = argsJson.toNativeUtf8();

    try {
      final resultPtr = _instanceInvoke(
        _instPtr,
        nameCString.cast<Char>(),
        argsCString.cast<Char>(),
      );
      if (resultPtr == nullptr) {
        throw StateError(
          'Failed to invoke "$name": ${_getLastError()}',
        );
      }
      final resultJson = resultPtr.cast<Utf8>().toDartString();
      _freeString(resultPtr);
      return jsonDecode(resultJson);
    } finally {
      calloc.free(nameCString);
      calloc.free(argsCString);
    }
  }

  /// Set up callback handler (not yet implemented)
  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    throw UnimplementedError(
      'setCallbackHandler not implemented for Skia renderer. '
      'See README for architecture plans.',
    );
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    throw UnimplementedError(
      'invokeCallback not implemented for Skia renderer. '
      'See README for architecture plans.',
    );
  }

  @override
  void dispose() {
    if (_instPtr != nullptr) {
      _instanceFree(_instPtr);
      _instPtr = nullptr;
    }
  }
}

/// Texture render target for Skia (external texture plumbing stubbed)
class SkiaTextureRenderTarget implements SlintTextureRenderTarget {
  final SkiaSlintComponent _component;

  SkiaTextureRenderTarget(this._component);

  @override
  SlintComponent get component => _component;

  @override
  int get width => 0; // ponytail: stubbed pending MTL/GL/Vulkan binding

  @override
  int get height => 0; // ponytail: stubbed pending MTL/GL/Vulkan binding

  @override
  void resize(int width, int height) {
    _component.setSize(width.toDouble(), height.toDouble());
  }

  /// Render to GPU texture (stubbed; returns false)
  @override
  bool render() {
    final result = _instanceRender(_component._instPtr);
    if (!result) {
      // Not yet implemented; see README
      return false;
    }
    return true;
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    throw UnimplementedError(
      'Pointer events not yet implemented for Skia. See README.',
    );
  }

  @override
  void dispatchKeyEvent(SlintKeyEvent event) {
    throw UnimplementedError(
      'Key events not yet implemented for Skia. See README.',
    );
  }

  /// Get the Flutter external texture ID (stubbed; throws UnimplementedError)
  @override
  int get textureId {
    throw UnimplementedError(
      'External texture plumbing not yet implemented for Skia. '
      'See README: requires platform-specific surface binding (Metal/GL/Vulkan). '
      'Current plan: slint_skia_instance_texture_id should return valid texture handle.',
    );
  }

  @override
  void dispose() {
    _component.dispose();
  }
}

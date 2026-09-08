import 'dart:ffi';
import 'dart:io';

DynamicLibrary _loadLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('libslint_skia_ffi.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libslint_skia_ffi.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('slint_skia_ffi.dll');
  } else if (Platform.isAndroid || Platform.isIOS) {
    // On mobile, the library is bundled with the app
    return DynamicLibrary.open('libslint_skia_ffi.so');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// The loaded slint_skia FFI library
final DynamicLibrary skiaLib = _loadLibrary();

import 'dart:ffi';
import 'dart:io';

DynamicLibrary Function()? _slintNativeLibraryOverride;

/// Override the native library loader for testing or custom build configurations.
set slintNativeLibraryOverride(DynamicLibrary Function()? override) {
  _slintNativeLibraryOverride = override;
}

/// Loads the slint-native-ffi native library.
///
/// Returns the platform-specific library:
/// - macOS/iOS: libslint_native_ffi.dylib
/// - Windows: slint_native_ffi.dll
/// - Others: libslint_native_ffi.so
DynamicLibrary openSlintNativeLibrary() {
  if (_slintNativeLibraryOverride != null) {
    return _slintNativeLibraryOverride!();
  }

  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('libslint_native_ffi.dylib');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('slint_native_ffi.dll');
  } else {
    return DynamicLibrary.open('libslint_native_ffi.so');
  }
}

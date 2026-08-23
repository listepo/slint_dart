import 'dart:ffi';
import 'dart:io';

DynamicLibrary Function()? _slintCompilerLibraryOverride;

/// Override the native library loader for testing or custom build configurations.
set slintCompilerLibraryOverride(DynamicLibrary Function()? override) {
  _slintCompilerLibraryOverride = override;
}

/// Loads the slint-compiler-ffi native library.
///
/// Returns the platform-specific library:
/// - macOS/iOS: libslint_compiler_ffi.dylib
/// - Windows: slint_compiler_ffi.dll
/// - Others: libslint_compiler_ffi.so
DynamicLibrary openSlintCompilerLibrary() {
  if (_slintCompilerLibraryOverride != null) {
    return _slintCompilerLibraryOverride!();
  }

  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('libslint_compiler_ffi.dylib');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('slint_compiler_ffi.dll');
  } else {
    return DynamicLibrary.open('libslint_compiler_ffi.so');
  }
}

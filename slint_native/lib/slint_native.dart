/// Slint runtime for Flutter via Rust FFI — slint-interpreter + software renderer.
///
/// Provides software-rendered [SlintEngine], [SlintComponent], and [SlintSoftwareRenderTarget]
/// implementations backed by Rust's Slint interpreter and MinimalSoftwareWindow.
library slint_native;

export 'src/library.dart';
export 'src/native_engine.dart';

/// Core abstractions for embedding the Slint UI toolkit in Flutter.
///
/// Backend-agnostic: `slint_native` (software renderer) and `slint_skia`
/// (Skia/GPU renderer) provide the implementations.
library;

export 'src/component.dart';
export 'src/engine.dart';
export 'src/events.dart';
export 'src/render_target.dart';

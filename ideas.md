# Ideas

- Optional: regenerate `packages/slint_skia/lib/src/bindings.g.dart` with ffigen (drops stale `slint_skia_instance_texture_id`). Platform entry points stay hand-declared `@Native` in `skia_native.dart`; local ffigen may remain banned — run only when allowed.

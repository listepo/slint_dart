import 'render_target.dart';

/// A compiled, instantiable component.
///
/// Mirrors `slint_interpreter::ComponentDefinition`.
abstract interface class SlintComponentDefinition {
  String get name;

  SlintComponent instantiate();

  void dispose();
}

typedef SlintCallbackHandler = Object? Function(List<Object?> arguments);

/// Reads a `.slint` asset and instantiates a component from it, for
/// [SlintComponent.load]. Implemented by backends that compile at runtime.
typedef SlintComponentLoader = Future<SlintSoftwareComponent> Function(
  String path,
  String? component,
);

/// A live component instance.
///
/// Mirrors `slint_interpreter::ComponentInstance`. Property and callback
/// values are plain Dart values (bool, num, String — richer types as the
/// backends grow).
abstract interface class SlintComponent {
  /// Loads a `.slint` asset and instantiates a component from it.
  ///
  /// [path] is an asset key, so the file must be declared under
  /// `flutter: assets:` — and therefore ships in every build mode. This is
  /// for a `.slint` the app means to ship and compile at runtime; a generated
  /// wrapper's `load()` already carries its own source and bundles nothing.
  ///
  /// [component] names which exported component to instantiate and may be
  /// omitted when the file exports exactly one — the compiler returns
  /// components unordered, so with several exports there is no meaningful
  /// "first" to fall back on.
  ///
  /// Reading a `.slint` file at runtime means compiling it at runtime, so this
  /// needs a backend that can: `slint_interpreter` registers itself the first
  /// time you touch it, or call its `useSlintInterpreter()` at startup. The
  /// AOT backend that ships in release compiles components at build time and
  /// has no runtime compiler, so this is interpreter-only.
  ///
  /// ```dart
  /// final component = await SlintComponent.load('lib/todo.slint');
  /// runApp(SlintView(target: component.renderTarget));
  /// ```
  static Future<SlintSoftwareComponent> load(String path, {String? component}) {
    final loader = SlintComponent.loader;
    if (loader == null) {
      throw StateError(
        "SlintComponent.load('$path') has no backend that can compile at "
        'runtime. Depend on slint_interpreter and call useSlintInterpreter() '
        'before loading, or use a generated wrapper.load() instead.',
      );
    }
    return loader(path, component);
  }

  /// The backend [load] goes through. Set by whichever package can compile
  /// `.slint` source at runtime; reading an asset is its job too, which keeps
  /// this file free of any Flutter import.
  static SlintComponentLoader? loader;

  Object? getProperty(String name);

  void setProperty(String name, Object? value);

  void setCallbackHandler(String name, SlintCallbackHandler handler);

  Object? invokeCallback(String name, List<Object?> arguments);

  void dispose();
}

/// A live instance that renders through a software target — satisfied by both
/// the interpreter instances (`slint_interpreter`) and the AOT-compiled ones
/// (`slint_compiler`).
abstract interface class SlintSoftwareComponent implements SlintComponent {
  SlintSoftwareRenderTarget get renderTarget;
}

/// A live instance whose accessibility tree can be inspected.
///
/// This is what lets a test find an element inside a Slint UI — which Flutter
/// sees as a single opaque widget — and work out where on screen to click it.
/// `slint_patrol` builds Patrol finders on top of it.
///
/// Descriptors are decoded JSON maps, like the property bridge: `id`,
/// `typeName`, `role`, `label`, `value`, `placeholder`, `description`,
/// `checked`, `checkable`, `enabled`, `itemIndex`, `itemCount`, and the
/// element's `x`, `y`, `width`, `height` in Slint logical pixels relative to
/// the window.
abstract interface class SlintInspectableComponent implements SlintComponent {
  /// Finds elements in the accessibility tree. [kind] is `all`, `label`,
  /// `id`, or `type`; [needle] is the text to match, unused for `all`.
  List<Map<String, Object?>> queryElements(String kind, [String? needle]);
}

import 'dart:io';

import 'package:build/build.dart';
import 'package:slint_build/slint_build.dart' show packageRootFromConfig;

import 'src/emitter.dart';
import 'src/introspect.dart';
import 'src/package_config.dart';

/// Entry point for build_runner (wired up in `build.yaml`): turns every
/// `ui/**.slint` into `lib/**.g.dart` of typed wrappers.
///
/// The `.slint` files live outside `lib/` so they are plainly not Dart
/// sources and never part of the package's public API; the generated Dart
/// goes under `lib/` because that is the only place app code can import it
/// from. `ui/` is a build_runner source only when the app's `build.yaml`
/// lists it (see `examples/todo/build.yaml`).
Builder slintBuilder(BuilderOptions options) => _SlintBuilder();

/// `ui/<stem>.slint` → `<stem>`; the builder only ever sees such inputs.
String slintStem(AssetId input) =>
    input.path.substring('ui/'.length, input.path.length - '.slint'.length);

class _SlintBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '^ui/{{}}.slint': ['lib/{{}}.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final source = await buildStep.readAsString(input);

    // Which backends the wrapper can default to depends on what the package
    // actually depends on. Reading the pubspec through the build step keeps it
    // a tracked input, so adding a backend rebuilds the wrappers.
    final deps = runtimeDependencies(
      await buildStep.readAsString(AssetId(input.package, 'pubspec.yaml')),
    );

    // build_runner runs from the package root; resolve the introspect tool
    // through the package config (Isolate.resolvePackageUri is unavailable in
    // the AOT-compiled build script).
    final generatorRoot = packageRootFromConfig(
      findPackageConfigFrom(Directory.current),
      'slint_generator',
    );
    final schema = await introspectSlint(
      File(input.path).absolute.path,
      introspectManifest: generatorRoot.resolve('rust/Cargo.toml'),
    );

    final stem = slintStem(input);
    await buildStep.writeAsString(
      AssetId(input.package, 'lib/$stem.g.dart'),
      generateWrapperLibrary(
        schema,
        sourceName: input.pathSegments.last,
        // The name `load` answers to; the wrapper never reads it.
        assetPath: input.path,
        slintSource: source,
        aotLibrary: deps.contains('slint_compiler')
            ? '${stem.split('/').last}.aot.g.dart'
            : null,
        interpreter: deps.contains('slint_interpreter'),
      ),
    );
  }
}

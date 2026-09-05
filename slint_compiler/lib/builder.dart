import 'dart:io';

import 'package:build/build.dart';
import 'package:slint_build/slint_build.dart' show packageRootFromConfig;
import 'package:slint_generator/builder.dart' show slintStem;
import 'package:slint_generator/slint_generator.dart';

import 'src/generator.dart';

/// Entry point for build_runner (wired up in `build.yaml`): turns every
/// `ui/**.slint` into `lib/**.aot.g.dart` binding the AOT code asset — the
/// same `ui/` the build hook AOT-compiles, so the asset ids line up.
///
/// The typed API comes from the `*.g.dart` wrapper that `slint_generator`
/// emits alongside it.
Builder slintAotBuilder(BuilderOptions options) => _SlintAotBuilder();

class _SlintAotBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '^ui/{{}}.slint': ['lib/{{}}.aot.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    await buildStep.readAsString(input); // dependency tracking

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

    final assetLibraryPath = '${slintStem(input)}.aot.g.dart';
    await buildStep.writeAsString(
      AssetId(input.package, 'lib/$assetLibraryPath'),
      generateDartFromSchema(
        schema,
        packageName: input.package,
        assetLibraryPath: assetLibraryPath,
        sourceName: input.pathSegments.last,
      ),
    );
  }
}

import 'dart:io';

import 'package:build/build.dart';
import 'package:slint_build/slint_build.dart' show packageRootFromConfig;

import 'src/emitter.dart';
import 'src/introspect.dart';
import 'src/package_config.dart';

/// Entry point for build_runner (wired up in `build.yaml`): turns every
/// `*.slint` into a sibling `*.g.dart` of typed wrappers.
Builder slintBuilder(BuilderOptions options) => _SlintBuilder();

class _SlintBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '.slint': ['.g.dart'],
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

    await buildStep.writeAsString(
      input.changeExtension('.g.dart'),
      generateWrapperLibrary(
        schema,
        sourceName: input.pathSegments.last,
        // Recorded for an app that ships this `.slint` as an asset; the
        // wrapper does not read it on its own.
        assetPath: input.path,
        slintSource: source,
        aotLibrary: deps.contains('slint_compiler')
            ? input.changeExtension('.aot.g.dart').pathSegments.last
            : null,
        interpreter: deps.contains('slint_interpreter'),
      ),
    );
  }
}

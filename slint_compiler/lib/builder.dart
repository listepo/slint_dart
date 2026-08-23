import 'dart:io';

import 'package:build/build.dart';
import 'package:slint_build/slint_build.dart' show packageRootFromConfig;

import 'src/generator.dart';
import 'src/introspect.dart';

/// Entry point for build_runner (wired up in `build.yaml`).
Builder slintBuilder(BuilderOptions options) => _SlintBuilder();

class _SlintBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '.slint': ['.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    if (!input.path.startsWith('lib/')) {
      throw StateError(
        '${input.path}: .slint files must live under lib/ — the build hook '
        'only AOT-compiles lib/**.slint, and the generated wrapper binds to '
        'that code asset.',
      );
    }
    await buildStep.readAsString(input); // dependency tracking

    // build_runner runs from the package root; resolve slint_compiler's
    // introspect tool through the package config (Isolate.resolvePackageUri
    // is unavailable in the AOT-compiled build script).
    final packageConfig =
        File('.dart_tool/package_config.json').absolute.uri;
    final compilerRoot = packageRootFromConfig(packageConfig, 'slint_compiler');
    final schema = await introspectSlint(
      File(input.path).absolute.path,
      compilerManifest: compilerRoot.resolve('rust/Cargo.toml'),
    );

    final outputId = input.changeExtension('.g.dart');
    await buildStep.writeAsString(
      outputId,
      generateDartFromSchema(
        schema,
        packageName: input.package,
        assetLibraryPath: outputId.path.substring('lib/'.length),
        sourceName: input.pathSegments.last,
      ),
    );
  }
}

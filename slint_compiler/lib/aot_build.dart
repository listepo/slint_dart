import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';
import 'package:slint_generator/slint_generator.dart' show introspectSlint;

import 'src/rust_glue.dart';

/// App build hook: AOT-compiles every `lib/**.slint` of the package into one
/// cdylib — slint-build codegen plus generated C ABI glue, no
/// slint-interpreter — and bundles it as one code asset per `.slint` file,
/// with id `package:<app>/<path>.g.dart` matching the wrappers the
/// `slint_compiler` builder generates.
///
/// Wire it up as the app's `hook/build.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:slint_compiler/aot_build.dart';
///
/// void main(List<String> args) => build(args, buildSlintAot);
/// ```
Future<void> buildSlintAot(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;
  // The AOT dylib ships only in release/profile builds; debug builds (incl.
  // `flutter test`) use the slint_interpreter package. In Flutter,
  // linkingEnabled == true exactly for the non-debug (AOT) modes.
  if (!input.config.linkingEnabled) return;

  final libDir = Directory.fromUri(input.packageRoot.resolve('lib/'));
  final slintFiles = !libDir.existsSync()
      ? <File>[]
      : (libDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.slint'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));
  if (slintFiles.isEmpty) return;

  final packageConfig = findPackageConfig(input);
  final compilerRoot = packageRootFromConfig(packageConfig, 'slint_compiler');
  final generatorRoot = packageRootFromConfig(packageConfig, 'slint_generator');
  final slintCoreCrate =
      packageRootFromConfig(packageConfig, 'slint').resolve('rust/');

  final files = <SlintAotFile>[];
  final assetNames = <String>[];
  final libPath = libDir.uri.toFilePath();
  for (final f in slintFiles) {
    final relative = f.path.substring(libPath.length);
    final schema = await introspectSlint(
      f.path,
      introspectManifest: generatorRoot.resolve('rust/Cargo.toml'),
    );
    files.add(SlintAotFile(
      stem: relative
          .substring(0, relative.length - '.slint'.length)
          .replaceAll(Platform.pathSeparator, '_'),
      source: f.readAsStringSync(),
      schema: schema,
    ));
    assetNames.add(
      '${relative.substring(0, relative.length - '.slint'.length)}.aot.g.dart'
          .replaceAll(Platform.pathSeparator, '/'),
    );
  }

  final crateDir =
      Directory.fromUri(input.outputDirectoryShared.resolve('slint_aot/'));
  emitAotCrate(
    crateDir,
    files: files,
    slintCoreCratePath: slintCoreCrate.toFilePath(),
  );

  await buildCargoCrate(
    input,
    output,
    crateName: 'slint-dart-aot',
    manifestPath: crateDir.uri.resolve('Cargo.toml'),
    assetNames: assetNames,
    sourceDirs: [
      input.packageRoot.resolve('lib/'),
      // Regenerate when the glue generator or the introspect tool change.
      compilerRoot.resolve('lib/'),
      generatorRoot.resolve('rust/'),
    ],
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';
import 'package:slint_generator/slint_generator.dart' show introspectSlint;

import 'src/generator.dart';
import 'src/rust_glue.dart';

/// App build hook: AOT-compiles every `ui/**.slint` of the package into one
/// staticlib — slint-build codegen plus generated C ABI glue, no
/// slint-interpreter — and routes it to the app's link hook ([ToLinkHook]),
/// which links the final dylib keeping only the components the app uses (see
/// `aot_link.dart`). One code asset per `.slint` file, with id
/// `package:<app>/<path>.aot.g.dart` matching the wrappers the
/// `slint_compiler` builder generates.
///
/// Wire it up as the app's `hook/build.dart` (with `hook/link.dart` calling
/// `linkSlintAot`):
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

  // `.slint` files live under `ui/`, not `lib/`: they are not Dart, and the
  // release bundle must not ship them — see `slint_generator`'s builder.
  final uiDir = Directory.fromUri(input.packageRoot.resolve('ui/'));
  final slintFiles = !uiDir.existsSync()
      ? <File>[]
      : (uiDir
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
  final uiPath = uiDir.uri.toFilePath();
  for (final f in slintFiles) {
    final relative = f.path.substring(uiPath.length);
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

  final build = await runCargoBuild(
    input,
    output,
    crateName: 'slint-dart-aot',
    manifestPath: crateDir.uri.resolve('Cargo.toml'),
    artifactKind: 'staticlib',
    // Makes rustc print the `native-static-libs:` note — the exact linker
    // line the staticlib needs — which the link hook replays when it links
    // the final dylib.
    extraEnv: const {'RUSTFLAGS': '--print=native-static-libs'},
    sourceDirs: [
      input.packageRoot.resolve('ui/'),
      // Regenerate when the glue generator or the introspect tool change.
      compilerRoot.resolve('lib/'),
      generatorRoot.resolve('rust/'),
    ],
  );

  final linkFlags = _persistedNativeLinkFlags(
    crateDir: crateDir,
    triple: rustTriple(input.config.code),
    cargoOutput: build.cargoOutput,
  );

  // Everything the link hook needs, written next to the routed staticlib.
  final manifest = {
    'assetIds': assetNames,
    'sharedSymbols': aotSharedSymbols,
    'linkFlags': linkFlags,
    'components': [
      for (var i = 0; i < files.length; i++)
        for (final c in files[i].schema.components)
          {
            'name': c.name,
            'library': 'package:${input.packageName}/${assetNames[i]}',
            'newExtern': aotNewExternName(c.name),
            'symbols': aotComponentSymbols(c.name),
          },
    ],
  };
  File.fromUri(input.outputDirectory.resolve(aotLinkManifestName))
      .writeAsStringSync(jsonEncode(manifest));

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetNames.first,
      linkMode: StaticLinking(),
      file: build.artifact,
    ),
    routing: ToLinkHook(input.packageName),
  );
}

/// The flag list from rustc's `native-static-libs:` note in [cargoOutput],
/// or null when the note is absent.
List<String>? nativeStaticLibsNote(String cargoOutput) {
  const marker = 'native-static-libs:';
  for (final line in cargoOutput.split('\n').reversed) {
    final i = line.indexOf(marker);
    if (i < 0) continue;
    final flags = line.substring(i + marker.length).trim();
    return flags.isEmpty ? const [] : flags.split(RegExp(r'\s+'));
  }
  return null;
}

/// Returns the linker flags for the staticlib, persisting them under
/// [crateDir] per [triple]: rustc prints the note only when it actually
/// reruns, so cached cargo builds fall back to the stored line.
List<String> _persistedNativeLinkFlags({
  required Directory crateDir,
  required String triple,
  required String cargoOutput,
}) {
  final store = File('${crateDir.path}/native-link-flags.$triple.txt');
  final fresh = nativeStaticLibsNote(cargoOutput);
  if (fresh != null) {
    store.writeAsStringSync(fresh.join(' '));
    return fresh;
  }
  if (store.existsSync()) {
    final stored = store.readAsStringSync().trim();
    return stored.isEmpty ? const [] : stored.split(RegExp(r'\s+'));
  }
  throw StateError(
    'cargo reported no native-static-libs note and none is stored at '
    '${store.path}; delete ${crateDir.path}/target to force a rebuild',
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:bazel_worker/driver.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Builds [crateName] with cargo (through a bazel_worker persistent worker)
/// and bundles the produced cdylib as the code asset
/// `package:<input.packageName>/<assetName>`.
///
/// [sourceDirs] are the directories whose `*.rs` / `*.toml` / `*.slint` /
/// `*.h` files invalidate the hook cache (the crate itself plus in-repo path
/// dependencies).
///
/// Profile selection ("debug"/"release") comes from the app pubspec:
///
/// ```yaml
/// hooks:
///   user_defines:
///     <package>:
///       profile: debug
/// ```
///
/// and defaults to `release` (debug builds of the Slint renderer are too slow
/// to be a useful default). Only user-defines are honored — they are part of
/// the hook input, so switching profile correctly invalidates the hook cache.
Future<void> buildCargoCrate(
  BuildInput input,
  BuildOutputBuilder output, {
  required String crateName,
  String assetName = 'src/bindings.g.dart',
  Iterable<String>? assetNames,
  Uri? manifestPath,
  Iterable<Uri> sourceDirs = const [],
  Iterable<Uri> extraDependencies = const [],
}) async {
  if (!input.config.buildCodeAssets) return;
  if (input.config.code.linkModePreference == LinkModePreference.static) {
    throw UnsupportedError(
      '$crateName only supports dynamic linking (cdylib), '
      'but the build requested static.',
    );
  }

  final result = await runCargoBuild(
    input,
    output,
    crateName: crateName,
    manifestPath: manifestPath,
    sourceDirs: sourceDirs,
    extraDependencies: extraDependencies,
  );

  for (final name in assetNames ?? [assetName]) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: name,
        linkMode: DynamicLoadingBundled(),
        file: result.artifact,
      ),
    );
  }
}

/// Result of [runCargoBuild]: the artifact copied into the hook's output
/// directory, plus cargo's diagnostic output (e.g. to read rustc's
/// `native-static-libs:` note when building a staticlib).
typedef CargoBuildResult = ({Uri artifact, String cargoOutput});

/// Builds [crateName] with cargo (through the persistent worker), copies the
/// produced artifact into `input.outputDirectory`, and registers [sourceDirs]
/// as hook dependencies. Does not emit any asset — callers decide how the
/// artifact ships (see [buildCargoCrate] for the plain cdylib case).
///
/// [artifactKind] is `cdylib` (default) or `staticlib` and selects which
/// cargo artifact is picked up. [extraEnv] is merged over the cross-compile
/// environment for the cargo invocation.
Future<CargoBuildResult> runCargoBuild(
  BuildInput input,
  BuildOutputBuilder output, {
  required String crateName,
  Uri? manifestPath,
  String artifactKind = 'cdylib',
  Iterable<Uri> sourceDirs = const [],
  Iterable<Uri> extraDependencies = const [],
  Map<String, String> extraEnv = const {},
}) async {
  final code = input.config.code;
  final triple = rustTriple(code);
  final profile = resolveCargoProfile(input);
  final manifest = manifestPath ?? input.packageRoot.resolve('rust/Cargo.toml');

  final request = WorkRequest(
    arguments: [
      jsonEncode({
        'manifestPath': manifest.toFilePath(),
        'crateName': crateName,
        'targetTriple': triple,
        'cargoProfile': profile == 'debug' ? 'dev' : 'release',
        'artifactKind': artifactKind,
        'extraEnv': {..._crossCompileEnv(code, triple), ...extraEnv},
      }),
    ],
  );

  final packageConfig = findPackageConfig(input);
  final workerScript = packageRootFromConfig(packageConfig, 'slint_build')
      .resolve('bin/cargo_worker.dart');
  final dart = _dartExecutable();
  final driver = BazelWorkerDriver(
    () => Process.start(dart, [
      '--packages=${packageConfig.toFilePath()}',
      workerScript.toFilePath(),
      '--persistent_worker',
    ]),
    maxWorkers: 1,
    maxIdleWorkers: 1,
    maxRetries: 1,
  );

  final WorkResponse response;
  try {
    response = await driver.doWork(request);
  } finally {
    await driver.terminateWorkers();
  }

  if (response.exitCode != 0) {
    throw ProcessException(
      'cargo',
      ['build', '-p', crateName, '--target', triple],
      _tail(response.output, 120),
      response.exitCode,
    );
  }
  final artifactLine = response.output
      .split('\n')
      .lastWhere((l) => l.startsWith('ARTIFACT:'), orElse: () => '');
  if (artifactLine.isEmpty) {
    throw StateError(
      'cargo worker reported success but no artifact for $crateName:\n'
      '${_tail(response.output, 40)}',
    );
  }
  final artifact = File(artifactLine.substring('ARTIFACT:'.length).trim());

  final bundled = File.fromUri(
    input.outputDirectory.resolve(artifact.uri.pathSegments.last),
  );
  await bundled.parent.create(recursive: true);
  await artifact.copy(bundled.path);

  for (final uri in _dependencyFiles(input, sourceDirs)) {
    output.dependencies.add(uri);
  }
  output.dependencies.addAll(extraDependencies);
  // The worker script is resolved through the package config, not
  // [sourceDirs], but a syntax error in it surfaces as a hook failure in
  // whichever package builds first — track it so edits rebuild.
  output.dependencies.add(workerScript);

  return (artifact: bundled.uri, cargoOutput: response.output);
}

/// `debug` or `release`, from the `profile` user-define; defaults to release.
String resolveCargoProfile(BuildInput input) {
  final raw = input.userDefines['profile'];
  return switch (raw) {
    null || '' => 'release',
    'release' => 'release',
    'debug' || 'dev' => 'debug',
    _ => throw ArgumentError(
        'Invalid `profile` user-define for ${input.packageName}: "$raw". '
        'Use "debug" or "release".',
      ),
  };
}

/// Maps the hook's target OS/architecture to a Rust target triple.
String rustTriple(CodeConfig code) {
  final os = code.targetOS;
  final arch = code.targetArchitecture;
  final triple = switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.iOS, Architecture.arm64) => code.iOS.targetSdk == IOSSdk.iPhoneSimulator
        ? 'aarch64-apple-ios-sim'
        : 'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.linux, Architecture.arm) => 'armv7-unknown-linux-gnueabihf',
    (OS.linux, Architecture.riscv64) => 'riscv64gc-unknown-linux-gnu',
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.android, Architecture.ia32) => 'i686-linux-android',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    _ => null,
  };
  if (triple == null) {
    throw UnsupportedError('No Rust target triple for $os/$arch');
  }
  return triple;
}


/// Env-var names cargo and the `cc` crate expect for [triple].
///
/// Exposed for tests: cargo uppercases the triple; `cc` keeps its case.
({String cargoLinkerKey, String ccKey, String arKey}) crossCompileEnvKeys(
  String triple,
) {
  final cargoTriple =
      triple.toUpperCase().replaceAll('-', '_').replaceAll('.', '_');
  final ccTriple = triple.replaceAll('-', '_').replaceAll('.', '_');
  return (
    cargoLinkerKey: 'CARGO_TARGET_${cargoTriple}_LINKER',
    ccKey: 'CC_$ccTriple',
    arKey: 'AR_$ccTriple',
  );
}
Map<String, String> _crossCompileEnv(CodeConfig code, String triple) {
  final env = <String, String>{};
  final os = code.targetOS;
  if (os == OS.macOS) {
    env['MACOSX_DEPLOYMENT_TARGET'] = '${code.macOS.targetVersion}.0';
  } else if (os == OS.iOS) {
    env['IPHONEOS_DEPLOYMENT_TARGET'] = '${code.iOS.targetVersion}.0';
  } else if (os == OS.android) {
    final compiler = code.cCompiler?.compiler;
    if (compiler != null) {
      final binDir = File.fromUri(compiler).parent;
      final api = code.android.targetNdkApi;
      // NDK clang wrappers are named after the *clang* triple, which differs
      // from the Rust triple for 32-bit ARM.
      final clangTriple =
          triple == 'armv7-linux-androideabi' ? 'armv7a-linux-androideabi' : triple;
      final ext = Platform.isWindows ? '.cmd' : '';
      final wrapper = '${binDir.path}${Platform.pathSeparator}$clangTriple$api-clang$ext';
      // cargo wants CARGO_TARGET_<TRIPLE>_LINKER uppercased with `-`/`.` as `_`.
      // The `cc` crate looks up CC_/AR_ with the target's own case
      // (`CC_aarch64_linux_android`, not `CC_AARCH64_LINUX_ANDROID`).
      final keys = crossCompileEnvKeys(triple);
      env[keys.cargoLinkerKey] = wrapper;
      env[keys.ccKey] = wrapper;
      final archiver = code.cCompiler?.archiver;
      if (archiver != null) {
        env[keys.arKey] = archiver.toFilePath();
      }
    }
  }
  return env;
}

Iterable<Uri> _dependencyFiles(BuildInput input, Iterable<Uri> sourceDirs) sync* {
  const exts = ['.rs', '.toml', '.slint', '.h', '.dart'];
  for (final dirUri in sourceDirs) {
    final dir = Directory.fromUri(dirUri);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.contains('${Platform.pathSeparator}target${Platform.pathSeparator}')) {
        continue;
      }
      if (exts.any(path.endsWith)) yield entity.uri;
    }
  }
  // Workspace Cargo.lock pins crate versions.
  var dir = Directory.fromUri(input.packageRoot);
  for (var i = 0; i < 6; i++) {
    final lock = File('${dir.path}${Platform.pathSeparator}Cargo.lock');
    if (lock.existsSync()) {
      yield lock.uri;
      break;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
}

/// The `.dart_tool/package_config.json` governing this hook invocation,
/// found by walking up from the shared output directory.
Uri findPackageConfig(BuildInput input) {
  var dir = Directory.fromUri(input.outputDirectoryShared);
  for (var i = 0; i < 15; i++) {
    final candidate = File(
      '${dir.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
    );
    if (candidate.existsSync()) return candidate.uri;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  final fromPlatform = Platform.packageConfig;
  if (fromPlatform != null) return Uri.base.resolve(fromPlatform);
  throw StateError(
    'package_config.json not found above ${input.outputDirectoryShared}',
  );
}

/// Root directory of [packageName] according to [packageConfig].
Uri packageRootFromConfig(Uri packageConfig, String packageName) {
  final json =
      jsonDecode(File.fromUri(packageConfig).readAsStringSync())
          as Map<String, Object?>;
  final packages = (json['packages'] as List).cast<Map<String, Object?>>();
  final entry = packages.firstWhere(
    (p) => p['name'] == packageName,
    orElse: () => throw StateError(
      '$packageName not found in ${packageConfig.toFilePath()}',
    ),
  );
  var rootUri = entry['rootUri'] as String;
  if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
  return packageConfig.resolve(rootUri);
}

String _dartExecutable() {
  final exe = Platform.resolvedExecutable;
  final base = exe.split(Platform.pathSeparator).last.toLowerCase();
  if (base == 'dart' || base == 'dart.exe') return exe;
  if (base.startsWith('dartaotruntime')) {
    // Hooks may run under dartaotruntime; the JIT `dart` sits next to it.
    final ext = base.endsWith('.exe') ? '.exe' : '';
    final sibling = File(
      '${File(exe).parent.path}${Platform.pathSeparator}dart$ext',
    );
    if (sibling.existsSync()) return sibling.path;
  }
  return 'dart'; // PATH fallback
}

String _tail(String text, int lines) {
  final all = text.split('\n');
  return all.length <= lines ? text : all.sublist(all.length - lines).join('\n');
}

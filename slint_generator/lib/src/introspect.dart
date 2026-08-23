import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'schema.dart';

/// Runs the `slint-introspect` tool (cargo) on [slintPath] and returns the
/// typed public interface of its exported components.
///
/// [introspectManifest] points at slint_generator's `rust/Cargo.toml`; when
/// null it is resolved through the package config (works under `dart run`,
/// not in AOT-compiled contexts such as build hooks — those must pass it).
Future<SlintSchema> introspectSlint(
  String slintPath, {
  Uri? introspectManifest,
}) async {
  final manifest = introspectManifest ?? _defaultManifest();
  final result = await Process.run('cargo', [
    'run',
    '--quiet',
    '--manifest-path',
    manifest.toFilePath(),
    '--',
    slintPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'slint-introspect failed for $slintPath:\n${result.stdout}${result.stderr}',
    );
  }
  return SlintSchema.fromJson(
    jsonDecode(result.stdout as String) as Map<String, Object?>,
  );
}

Uri _defaultManifest() {
  final pkg = Isolate.resolvePackageUriSync(Uri.parse('package:slint_generator/'));
  if (pkg == null) {
    throw StateError(
      'cannot resolve package:slint_generator; pass introspectManifest explicitly',
    );
  }
  return pkg.resolve('../rust/Cargo.toml');
}

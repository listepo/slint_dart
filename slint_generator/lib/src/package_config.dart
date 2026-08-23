import 'dart:io';

/// Locates the `.dart_tool/package_config.json` governing [from], walking up
/// so that members of a pub workspace find the shared config at the workspace
/// root rather than expecting one in their own directory.
///
/// build_runner runs the build script from the package root, so builders can
/// call this with `Directory.current`; `Isolate.resolvePackageUriSync` is
/// unavailable there (the script is AOT-compiled).
Uri findPackageConfigFrom(Directory from) {
  var dir = from.absolute;
  while (true) {
    final candidate = File.fromUri(
      dir.uri.resolve('.dart_tool/package_config.json'),
    );
    if (candidate.existsSync()) {
      return candidate.uri;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'no .dart_tool/package_config.json found from ${from.path} upwards — '
        'run `dart pub get` first',
      );
    }
    dir = parent;
  }
}

import 'dart:io';

import 'package:slint_compiler/slint_compiler.dart';
import 'package:slint_generator/slint_generator.dart';

/// Usage: `dart run slint_compiler <input.slint> [output.g.dart]`
///
/// Writes both generated libraries: the typed wrapper `<output>.g.dart` and
/// the AOT backend `<output>.aot.g.dart` next to it. Default output:
/// `<input directory>/<basename>.g.dart`. It must live under a package's
/// `lib/` — the AOT backend binds to the code asset
/// `package:<package>/<path under lib>` built by the app's hook.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: dart run slint_compiler <input.slint> [output.g.dart]');
    exit(64);
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('not found: ${input.path}');
    exit(66);
  }
  final output = File(
    args.length == 2
        ? args[1]
        : input.path.replaceFirst(RegExp(r'\.slint$'), '.g.dart'),
  );

  // Locate the enclosing package: walk up from the output to pubspec.yaml.
  final sep = Platform.pathSeparator;
  var dir = output.absolute.parent;
  Directory? packageRoot;
  while (true) {
    if (File('${dir.path}${sep}pubspec.yaml').existsSync()) {
      packageRoot = dir;
      break;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  if (packageRoot == null) {
    stderr.writeln('${output.path}: not inside a Dart package (no pubspec.yaml found)');
    exit(64);
  }
  final pubspec = File('${packageRoot.path}${sep}pubspec.yaml').readAsStringSync();
  final packageName =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);
  if (packageName == null) {
    stderr.writeln('${packageRoot.path}${sep}pubspec.yaml: no `name:` entry');
    exit(64);
  }
  final libDir = '${packageRoot.path}${sep}lib$sep';
  if (!output.absolute.path.startsWith(libDir)) {
    stderr.writeln('${output.path}: output must live under ${packageRoot.path}${sep}lib$sep');
    exit(64);
  }

  final schema = await introspectSlint(input.absolute.path);
  final sourceName = input.uri.pathSegments.last;

  final aotOutput = File(
    output.path.replaceFirst(RegExp(r'(\.g)?\.dart$'), '.aot.g.dart'),
  );

  output.writeAsStringSync(generateWrapperLibrary(
    schema,
    sourceName: sourceName,
    slintSource: input.readAsStringSync(),
    // The AOT backend is always written next to the wrapper here; the
    // interpreter is only a default when the package can import it.
    aotLibrary: aotOutput.uri.pathSegments.last,
    interpreter: runtimeDependencies(pubspec).contains('slint_interpreter'),
  ));

  aotOutput.writeAsStringSync(generateDartFromSchema(
    schema,
    packageName: packageName,
    assetLibraryPath:
        aotOutput.absolute.path.substring(libDir.length).replaceAll(sep, '/'),
    sourceName: sourceName,
  ));
  stdout.writeln('generated ${output.path} and ${aotOutput.path}');
}

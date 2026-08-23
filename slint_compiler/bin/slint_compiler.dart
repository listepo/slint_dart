import 'dart:io';

import 'package:slint_compiler/slint_compiler.dart';

/// Usage: `dart run slint_compiler <input.slint> [output.g.dart]`
///
/// Default output: `<input directory>/<basename>.g.dart`. The output must
/// live under a package's `lib/` — the generated wrapper binds to the code
/// asset `package:<package>/<path under lib>` built by the app's hook.
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
  final code = generateDartFromSchema(
    schema,
    packageName: packageName,
    assetLibraryPath:
        output.absolute.path.substring(libDir.length).replaceAll(sep, '/'),
    sourceName: input.uri.pathSegments.last,
  );
  output.writeAsStringSync(code);
  stdout.writeln('generated ${output.path}');
}

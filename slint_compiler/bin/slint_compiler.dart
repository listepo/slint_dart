import 'dart:io';

import 'package:slint_compiler/slint_compiler.dart';

/// Usage: `dart run slint_compiler <input.slint> [output.g.dart]`
///
/// Default output: `<input directory>/<basename>.g.dart`.
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
  final basename = input.uri.pathSegments.last;
  final output = File(
    args.length == 2
        ? args[1]
        : input.path.replaceFirst(RegExp(r'\.slint$'), '.g.dart'),
  );

  final code = await generateDart(
    input.readAsStringSync(),
    sourceName: basename,
  );
  output.writeAsStringSync(code);
  stdout.writeln('generated ${output.path}');
}

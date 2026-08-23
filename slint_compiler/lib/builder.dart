import 'dart:io';

import 'package:build/build.dart';

/// Entry point for build_runner (wired up in `build.yaml`).
Builder slintBuilder(BuilderOptions options) => _SlintBuilder();

/// Runs the `slint_compiler` CLI in a subprocess instead of calling
/// [generateDart] directly: the generator drives the slint_native FFI engine,
/// whose native asset only exists under `dart run` (build hooks). The
/// AOT-compiled build_runner script has no native assets.
class _SlintBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '.slint': ['.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final source = await buildStep.readAsString(input);
    final dir = await Directory.systemTemp.createTemp('slint_compiler');
    try {
      final inFile = File('${dir.path}/${input.pathSegments.last}')
        ..writeAsStringSync(source);
      final outPath = '${dir.path}/out.g.dart';
      final result = await Process.run(
        _dartExecutable(),
        ['run', 'slint_compiler', inFile.path, outPath],
      );
      if (result.exitCode != 0) {
        throw StateError(
          'slint_compiler failed on ${input.path}:\n'
          '${result.stdout}${result.stderr}',
        );
      }
      await buildStep.writeAsString(
        input.changeExtension('.g.dart'),
        File(outPath).readAsStringSync(),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  /// The build script runs under dartaotruntime; find the `dart` CLI.
  String _dartExecutable() {
    final self = File(Platform.resolvedExecutable);
    final name = Platform.isWindows ? 'dart.exe' : 'dart';
    if (self.uri.pathSegments.last == name) return self.path;
    final sibling = File('${self.parent.path}/$name');
    return sibling.existsSync() ? sibling.path : 'dart';
  }
}

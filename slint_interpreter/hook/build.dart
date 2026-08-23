import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
      // Interpreter runtime is the debug-mode backend; release/profile builds
      // ship the slint_compiler AOT dylib instead. In Flutter,
      // linkingEnabled == true exactly for the non-debug (AOT) modes.
      // ponytail: no override knob; add a user-define if a release build ever
      // needs the interpreter.
      if (input.config.linkingEnabled) return;
      final root = input.packageRoot;
      await buildCargoCrate(
        input,
        output,
        crateName: 'slint-interpreter-ffi',
        sourceDirs: [
          root.resolve('rust/'),
          root.resolve('../slint/rust/'),
          root.resolve('interpreter/'),
        ],
      );
    });

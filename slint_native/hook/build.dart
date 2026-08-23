import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
      final root = input.packageRoot;
      await buildCargoCrate(
        input,
        output,
        crateName: 'slint-native-ffi',
        sourceDirs: [
          root.resolve('rust/'),
          root.resolve('../slint/rust/'),
          root.resolve('../slint_interpreter/'),
        ],
      );
    });

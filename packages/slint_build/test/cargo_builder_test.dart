import 'package:slint_build/slint_build.dart';
import 'package:test/test.dart';

void main() {
  group('crossCompileEnvKeys', () {
    test('cargo uppercases; cc keeps target case', () {
      final keys = crossCompileEnvKeys('aarch64-linux-android');
      expect(keys.cargoLinkerKey, 'CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER');
      expect(keys.ccKey, 'CC_aarch64_linux_android');
      expect(keys.arKey, 'AR_aarch64_linux_android');
    });

    test('periods become underscores for both', () {
      final keys = crossCompileEnvKeys('thumbv8m.main-none-eabi');
      expect(keys.cargoLinkerKey, 'CARGO_TARGET_THUMBV8M_MAIN_NONE_EABI_LINKER');
      expect(keys.ccKey, 'CC_thumbv8m_main_none_eabi');
      expect(keys.arKey, 'AR_thumbv8m_main_none_eabi');
    });

    test('armv7 android triple', () {
      final keys = crossCompileEnvKeys('armv7-linux-androideabi');
      expect(keys.cargoLinkerKey, 'CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER');
      expect(keys.ccKey, 'CC_armv7_linux_androideabi');
    });
  });
}

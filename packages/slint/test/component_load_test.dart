import 'package:slint/slint_core.dart';
import 'package:test/test.dart';

/// Stands in for a generated wrapper instance; only identity matters here.
class _Fake implements SlintSoftwareComponent {
  var disposed = false;
  @override
  void dispose() => disposed = true;
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// A second wrapper type, for a file that exports two components.
class _Other extends _Fake {}

void main() {
  group('load', () {
    const path = 'ui/a.slint';
    tearDown(() => SlintComponent.unregister(path));

    test('returns what the wrapper registered, typed', () {
      SlintComponent.register<_Fake>(path, 'Dashboard', _Fake.new);

      final _Fake app = SlintComponent.load(path);
      expect(app, isA<_Fake>());
      expect(SlintComponent.load<_Fake>(path), isNot(same(app)),
          reason: 'every load is a fresh instance');
    });

    test('takes exactly one .slint file', () {
      SlintComponent.register<_Fake>(path, 'Dashboard', _Fake.new);
      for (final notSlint in ['ui/a.txt', 'ui/a', 'ui/', '']) {
        expect(
            () => SlintComponent.load(notSlint),
            throwsA(isA<ArgumentError>()
                .having((e) => e.message, 'message', 'not a .slint file')
                .having((e) => e.invalidValue, 'value', notSlint)),
            reason: notSlint);
      }
    });

    test('with nothing registered it says what to do about it', () {
      expect(
        () => SlintComponent.load(path),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains(path), contains('register()'), contains('loadAsset')))),
      );
    });

    test('a file with several components needs a name or a type', () {
      SlintComponent.register<_Fake>(path, 'Dashboard', _Fake.new);
      SlintComponent.register<_Other>(path, 'Settings', _Other.new);

      expect(SlintComponent.load(path, component: 'Settings'), isA<_Other>());
      expect(SlintComponent.load<_Other>(path), isA<_Other>());
      expect(SlintComponent.load<_Fake>(path).runtimeType, _Fake);
      expect(
        () => SlintComponent.load(path),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('Dashboard'), contains('Settings')))),
      );
      expect(
        () => SlintComponent.load(path, component: 'Nope'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            allOf(contains('Dashboard'), contains('Settings')))),
      );
    });

    test('a type the registration does not satisfy is an error, not a leak',
        () {
      _Fake? made;
      SlintComponent.register<_Fake>(path, 'Dashboard', () => made = _Fake());

      expect(() => SlintComponent.load<_Other>(path), throwsStateError);
      expect(made?.disposed, isTrue);
    });

    test('registering again replaces', () {
      SlintComponent.register<_Fake>(path, 'Dashboard', _Fake.new);
      SlintComponent.register<_Other>(path, 'Dashboard', _Other.new);
      expect(SlintComponent.load(path), isA<_Other>());
    });
  });

  group('loadAsset', () {
    tearDown(() => SlintComponent.loader = null);

    test('goes through whichever backend installed itself', () async {
      final asked = <(String, String?)>[];
      SlintComponent.loader = (path, component) async {
        asked.add((path, component));
        return _Fake();
      };

      await SlintComponent.loadAsset('assets/ui/a.slint',
          component: 'Dashboard');

      expect(asked, [('assets/ui/a.slint', 'Dashboard')]);
    });

    test('with no runtime compiler it says what to do about it', () {
      // The AOT backend that ships in release has no compiler, so this is the
      // error a release build hits — it has to name the way out.
      expect(
        () => SlintComponent.loadAsset('assets/ui/a.slint'),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('assets/ui/a.slint'),
                contains('useSlintInterpreter')))),
      );
    });
  });
}

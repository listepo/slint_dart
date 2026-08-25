import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:todo_example/todo.g.dart';

/// `load()` is the one-call path from a `.slint` file to something on screen.
/// It takes the source the builder captured, so nothing has to be bundled —
/// see the `flutter:` section of `pubspec.yaml`. Passing `path:` opts into
/// reading an asset instead, for an app that ships a `.slint` on purpose.
void main() {
  final slintSource = File('lib/todo.slint').readAsStringSync();

  /// Stands in for an app that declared a `.slint` under `flutter: assets:`.
  /// Keys must be unique per test — `rootBundle` caches what it has read.
  void serveAsset(WidgetTester tester, String key, String contents) {
    tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final requested = utf8.decode(message!.buffer.asUint8List());
      if (requested != key) return null; // null is "no such asset"
      final bytes = Uint8List.fromList(utf8.encode(contents));
      return ByteData.view(bytes.buffer);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
  }

  // Reading the bundle is real I/O, which a testWidgets body's fake clock
  // never advances; runAsync hands it the real event loop.
  Future<T> loading<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> pumpTarget(WidgetTester tester, SlintSoftwareRenderTarget t) =>
      tester.pumpWidget(MaterialApp(home: SlintView(target: t)));

  // SlintView renders every frame off a Ticker, so the tree is never
  // quiescent and pumpAndSettle would spin until it times out.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('the generated load() renders without naming a backend',
      (tester) async {
    final app = await TodoApp.load();
    addTearDown(app.dispose);

    await pumpTarget(tester, app.renderTarget);
    await pumpFrames(tester);

    expect(find.byType(SlintView), findsOneWidget);
    expect(app.renderTarget.pixels.any((b) => b != 0), isTrue,
        reason: 'the loaded component should have drawn something');
  });

  testWidgets('the loaded component is live, not just pixels', (tester) async {
    final app = await TodoApp.load();
    addTearDown(app.dispose);

    final added = <String>[];
    app.onAddTodo(added.add);
    app.todoModel = const [TodoItem(title: 'from the source', checked: false)];

    await pumpTarget(tester, app.renderTarget);
    await pumpFrames(tester);

    expect(app.todoModel.single.title, 'from the source');
    app.invokeAddTodo('buy milk');
    expect(added, ['buy milk']);
  });

  testWidgets('nothing reads the bundle unless a path says so', (tester) async {
    // The whole point of the default: no asset is declared, so a wrapper that
    // reached for one would fail here rather than in someone's release build.
    var reads = 0;
    tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      reads++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));

    (await TodoApp.load()).dispose();
    expect(reads, 0);
  });

  testWidgets('passing a path compiles that asset instead', (tester) async {
    serveAsset(tester, 'assets/ui/todo.slint', slintSource);

    final app =
        await loading(tester, () => TodoApp.load(path: 'assets/ui/todo.slint'));
    addTearDown(app.dispose);

    await pumpTarget(tester, app.renderTarget);
    await pumpFrames(tester);

    expect(app.renderTarget.pixels.any((b) => b != 0), isTrue);
  });

  testWidgets('SlintComponent.load reaches a component by asset key',
      (tester) async {
    // The untyped entry point: no generated wrapper, just an asset key.
    useSlintInterpreter();
    serveAsset(tester, 'assets/ui/untyped.slint', slintSource);

    final component = await loading(
      tester,
      () => SlintComponent.load('assets/ui/untyped.slint',
          component: 'TodoApp'),
    );
    addTearDown(component.dispose);

    await pumpTarget(tester, component.renderTarget);
    await pumpFrames(tester);

    expect(component.renderTarget.pixels.any((b) => b != 0), isTrue);
  });

  testWidgets('naming no component is an error when the file exports several',
      (tester) async {
    // todo.slint also exports UnusedGadget, and the compiler hands components
    // back unordered — so there is no "first" to fall back on.
    useSlintInterpreter();
    serveAsset(tester, 'assets/ui/ambiguous.slint', slintSource);

    final error = await loading(tester, () async {
      try {
        (await SlintComponent.load('assets/ui/ambiguous.slint')).dispose();
        return null;
      } catch (e) {
        return e;
      }
    });

    expect(
        error,
        isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('TodoApp'), contains('UnusedGadget'))));
  });

  testWidgets('a missing asset says which key failed', (tester) async {
    useSlintInterpreter();
    final error = await loading(tester, () async {
      try {
        (await SlintComponent.load('assets/ui/nope.slint')).dispose();
        return null;
      } catch (e) {
        return e;
      }
    });

    expect('$error', contains('assets/ui/nope.slint'));
  });
}

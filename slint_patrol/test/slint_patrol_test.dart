import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:slint_patrol/slint_patrol.dart';

const _source = '''
import { Button, CheckBox, LineEdit } from "std-widgets.slint";

export component Form inherits Window {
    in-out property <string> typed: "";
    in-out property <int> taps: 0;

    VerticalLayout {
        edit := LineEdit {
            placeholder-text: "Name it";
            edited => { root.typed = self.text; }
        }
        agree := CheckBox { text: "I agree"; }
        Button {
            text: "Save";
            clicked => { root.taps += 1; }
        }
    }
}
''';

/// Compiles the source with the interpreter backend and returns the live
/// component — the same one a debug build of a real app would run.
SlintSoftwareComponent _liveComponent() {
  final engine = InterpreterSlintEngine();
  final defs = engine.compile(_source, path: 'test.slint');
  final def = defs.firstWhere((d) => d.name == 'Form');
  return def.instantiate() as SlintSoftwareComponent;
}

void main() {
  late SlintSoftwareComponent component;

  setUp(() => component = _liveComponent());
  tearDown(() => component.dispose());

  Widget app() => MaterialApp(
        home: Scaffold(body: SlintView(target: component.renderTarget)),
      );

  patrolWidgetTest('finds a Slint element by its label', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    final save = await $.slint('Save').resolve();
    expect(save.role, 'Button');
    expect(save.hasSize, isTrue,
        reason: 'geometry comes from layout, so it must be non-zero');
  });

  patrolWidgetTest('tapping drives the real component', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect(component.getProperty('taps'), 0);
    await $.slint('Save').tap();
    expect(component.getProperty('taps'), 1,
        reason: 'a Flutter gesture at the element should reach Slint');
  });

  patrolWidgetTest('a tap lands on the element it names, not a neighbour',
      ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect($.slintById('Form::agree').current.single.checked, isFalse);
    await $.slintById('Form::agree').tap();

    expect($.slintById('Form::agree').current.single.checked, isTrue);
    expect(component.getProperty('taps'), 0,
        reason: 'the button must not have been hit instead');
  });

  patrolWidgetTest('typing goes through the widget key path', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    await $.slintById('Form::edit').enterText('milk');

    expect(component.getProperty('typed'), 'milk');
    expect($.slintById('Form::edit').current.single.value, 'milk');
  });

  patrolWidgetTest('queries by id, type, and role', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect($.slintById('Form::agree').count, 1);
    expect($.slintByType('Button').count, 1);
    expect($.slintByRole('Button').current.single.label, 'Save');
    expect($.slintAll().count, greaterThan(4),
        reason: 'the tree includes the widgets own internals');
  });

  patrolWidgetTest('component properties are readable through the tester',
      ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    $.slintComponent().setProperty('taps', 7);
    expect($.slintComponent().getProperty('taps'), 7);
  });

  group('failure messages', () {
    patrolWidgetTest('a missing element says so', ($) async {
      await $.pumpWidget(app());
      await $.slintSettle();

      // Caught rather than matched with `throwsA`: resolving pumps frames,
      // and those pumps have to run in the test's own async flow.
      Object? caught;
      try {
        await $.slint('Nope').resolve(timeout: const Duration(seconds: 1));
      } catch (error) {
        caught = error;
      }
      expect(
        caught,
        isA<SlintPatrolException>()
            .having((e) => e.message, 'message', contains('Nope')),
      );
    });

    patrolWidgetTest('an ambiguous match asks you to narrow it', ($) async {
      await $.pumpWidget(app());
      await $.slintSettle();

      // `Text` shows up repeatedly inside the widgets themselves.
      final all = $.slintByType('Text');
      expect(all.count, greaterThan(1));
      await expectLater(
        all.resolve(),
        throwsA(isA<SlintPatrolException>()
            .having((e) => e.message, 'message', contains('narrow'))),
      );
      // ...and narrowing resolves it.
      expect((await all.first.resolve()).typeName, 'Text');
    });

    patrolWidgetTest('no SlintView is a clear error, not a crash', ($) async {
      await $.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(
        () => $.slint('Save').current,
        throwsA(isA<SlintPatrolException>()
            .having((e) => e.message, 'message', contains('no SlintView'))),
      );
    });
  });
}

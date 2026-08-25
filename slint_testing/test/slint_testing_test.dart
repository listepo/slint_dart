import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';

const _source = '''
import { Button, CheckBox, LineEdit } from "std-widgets.slint";

export component Form inherits Window {
    in-out property <string> title-text: "untitled";
    in property <bool> saved: false;
    callback save(name: string);
    callback reset();

    VerticalLayout {
        edit := LineEdit {
            placeholder-text: "Name it";
            text: root.title-text;
        }
        agree := CheckBox {
            text: "I agree";
            checked: false;
        }
        Button {
            text: "Save";
            clicked => { root.save(edit.text); }
        }
        Button {
            text: "Reset";
            clicked => { root.reset(); }
        }
    }
}

export component Other inherits Window {
    Text { text: "other"; }
}
''';

void main() {
  late SlintTestApp app;

  setUp(() => app = SlintTestApp.compile(_source, component: 'Form'));
  tearDown(() => app.dispose());

  group('compile', () {
    test('a lone exported component needs no name', () {
      final only = SlintTestApp.compile(
          'export component Only inherits Window { Text { text: "hi"; } }');
      addTearDown(only.dispose);
      expect(only.findAll(), isNotEmpty);
    });

    test('asks which component to test when the source exports several', () {
      expect(
        () => SlintTestApp.compile(_source),
        throwsA(isA<SlintTestException>()
            .having((e) => e.message, 'message', contains('Form, Other'))),
      );
    });

    test('names the components it did find when the wanted one is missing',
        () {
      expect(
        () => SlintTestApp.compile(_source, component: 'Nope'),
        throwsA(isA<SlintTestException>()
            .having((e) => e.message, 'message', contains('Form'))),
      );
    });

    test('reports compile errors', () {
      expect(
        () => SlintTestApp.compile('export component Broken { syntax('),
        throwsA(isA<SlintTestException>()),
      );
    });
  });

  group('queries', () {
    test('findByLabel matches the user-visible text', () {
      final save = app.findByLabel('Save');
      expect(save, hasLength(1));
      expect(save.single.role, 'Button');
    });

    test('findById uses component-qualified ids', () {
      expect(app.findById('Form::agree'), hasLength(1));
      expect(app.findById('Form::nonexistent'), isEmpty);
    });

    test('findByType matches the widget type', () {
      expect(app.findByType('Button'), hasLength(2));
    });

    test('findByRole filters the whole tree', () {
      expect(app.findByRole('Button').map((e) => e.label),
          containsAll(['Save', 'Reset']));
      // A widget repeats its role on the inner elements that implement it, so
      // match the checkbox itself rather than counting the hits.
      expect(app.findByRole('Checkbox').map((e) => e.id),
          contains('Form::agree'));
    });

    test('findAll descends into the widgets themselves', () {
      final all = app.findAll();
      expect(all.map((e) => e.typeName), contains('LineEdit'));
      // Not only the elements the component wrote: the tree continues into
      // each widget's own implementation.
      expect(all.map((e) => e.id), contains('LineEditBase::text-input'));
    });

    test('elements expose accessible state', () {
      final agree = app.findById('Form::agree').single;
      expect(agree.label, 'I agree');
      expect(agree.checked, isFalse);
      expect(agree.checkable, isTrue);
      expect(agree.enabled, isTrue);
      expect(app.findById('Form::edit').single.placeholder, 'Name it');
    });
  });

  group('interaction', () {
    test('click toggles a checkbox', () {
      expect(app.findById('Form::agree').single.checked, isFalse);
      app.findById('Form::agree').single.click();
      expect(app.findById('Form::agree').single.checked, isTrue);
    });

    test('click fires the callback the button is wired to', () {
      app.record('reset');
      app.findByLabel('Reset').single.click();
      expect(app.takeCalls().single.name, 'reset');
    });

    test('setValue types into a text input, and the callback sees it', () {
      app.record('save');
      app.findById('Form::edit').single.setValue('a title');
      app.findByLabel('Save').single.click();

      final calls = app.takeCalls();
      expect(calls, hasLength(1));
      expect(calls.single.name, 'save');
      expect(calls.single.args, ['a title']);
    });

    test('an element from a superseded query refuses to act', () {
      final save = app.findByLabel('Save').single;
      app.findByLabel('Reset'); // replaces the snapshot `save` indexes into
      expect(save.click, throwsA(isA<SlintTestException>()));
    });

    test('takeCalls drains the log', () {
      app.record('reset');
      app.findByLabel('Reset').single.click();
      expect(app.takeCalls(), hasLength(1));
      expect(app.takeCalls(), isEmpty);
    });
  });

  group('properties', () {
    test('round-trip through the JSON bridge', () {
      app.setProperty('title-text', 'from the test');
      expect(app.getProperty('title-text'), 'from the test');
      expect(app.findById('Form::edit').single.value, 'from the test');
    });

    test('invoke calls a callback directly', () {
      app.record('save');
      app.invoke('save', ['direct']);
      expect(app.takeCalls().single.args, ['direct']);
    });

    test('an unknown property is an error, not a silent null', () {
      expect(() => app.getProperty('nope'),
          throwsA(isA<SlintTestException>()));
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent and blocks later use', () {
      final other = SlintTestApp.compile(_source, component: 'Other');
      other.dispose();
      other.dispose();
      expect(other.findAll, throwsA(isA<SlintTestException>()));
    });

    test('mock time advances without real waiting', () {
      // No animation to observe here; the point is that it is callable and
      // does not wall-clock wait.
      final start = DateTime.now();
      app.elapse(const Duration(seconds: 5));
      expect(DateTime.now().difference(start), lessThan(const Duration(seconds: 1)));
    });
  });
}

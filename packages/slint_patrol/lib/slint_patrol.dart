/// Drive Slint UIs from Patrol tests.
///
/// Slint renders its whole UI into one Flutter widget, so Flutter's finders
/// see a single opaque box. This adds `$.slint(...)` finders that search the
/// live component's accessibility tree instead, then tap and type through
/// real Flutter gestures aimed at where the element sits on screen.
///
/// ```dart
/// await $.slintById('TodoApp::edit').enterText('buy milk');
/// await $.slint('Add').tap();
/// expect($.slintComponent().getProperty('todo-count'), 1);
/// ```
///
/// See [SlintPatrolTester] for the query methods and [SlintFinder] for what
/// you can do with a match.
library;

export 'src/patrol_tester_ext.dart' show SlintPatrolTester;
export 'src/slint_finder.dart'
    show SlintFinder, SlintMatch, SlintPatrolException;

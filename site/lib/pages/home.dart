import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:markdown/markdown.dart' as md;

import '../content/catalog.dart';
import '../content/highlight.dart';
import 'shell.dart';

// Code sample: condensed from guides/getting-started.md (steps 4 and 6).
const _helloSlint = '''
export component HelloApp inherits Window {
    preferred-width: 400px;
    preferred-height: 300px;
    title: "Hello Slint";

    in property <string> message: "Hello from Slint";

    VerticalLayout {
        padding: 16px;
        Text { text: root.message; font-size: 24px; }
    }
}''';

const _mainDart = '''
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HelloApp.register(); // once per component
  runApp(const MyApp());
}

// initState — loading is synchronous, no Future:
_app = SlintComponent.load('ui/hello.slint')
  ..message = 'Hello from Flutter';

// build:
SlintView(target: app.renderTarget)''';

// Install: verbatim from guides/getting-started.md, steps 1 and 5.
const _pubspec = '''
dependencies:
  slint: ^0.0.1
  slint_interpreter: ^0.0.1
  slint_compiler: ^0.0.1
  slint_generator: ^0.0.1
  hooks: ^2.2.0

dev_dependencies:
  build_runner: ^2.16.0''';

const _generate = 'dart run build_runner build --delete-conflicting-outputs';

// Features: each line restates a fact from the repository README.
const _features = <(String, String, String)>[
  (
    'Typed wrappers, generated',
    '<code>slint_generator</code> turns each <code>.slint</code> file into <code>foo.g.dart</code>: one typed class per component, with properties and callbacks as typed members.',
    '<path d="M8 6l-5 6 5 6M16 6l5 6-5 6"/>',
  ),
  (
    'Interpreter in debug, AOT in release',
    'The generated <code>defaultFactory</code> follows the Flutter build mode. <code>SlintComponent.load</code> is the whole call site; app code names neither backend.',
    '<path d="M4 7h10M4 17h16M18 4v6M8 14v6"/>',
  ),
  (
    'Tree-shaken release builds',
    'The link hook drops components no reachable Dart code uses. A release binary carries no interpreter path and no copy of the <code>.slint</code> text.',
    '<path d="M12 3v18M5 9l7-6 7 6M7 21h10"/>',
  ),
  (
    'Headless UI tests',
    '<code>slint_testing</code> exposes the accessibility tree: find elements by label, id, type or role, click and fill them in, under plain <code>dart test</code>.',
    '<path d="M9 12l2 2 4-4"/><rect x="3.5" y="3.5" width="17" height="17" rx="4"/>',
  ),
  (
    'Live end-to-end with Patrol',
    '<code>\$.slint(...)</code> finders act through real Flutter gestures, so one test can drive Flutter widgets, Slint elements and native UI.',
    '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3"/>',
  ),
  (
    'No manual cargo build',
    'Native-assets hooks build the Rust crates during <code>flutter run</code>, <code>build</code> and <code>test</code>, deriving target triple and toolchain from the build input.',
    '<path d="M4 17l6-6-6-6M12 19h8"/>',
  ),
];

/// Package rows parsed from packages/index.md, so the landing never drifts
/// from the package reference.
List<(String name, String roleHtml)> _packageRows() {
  final rows = <(String, String)>[];
  final src = File('web/content/packages/index.md').readAsLinesSync();
  final re = RegExp(r'^\|\s*\[([\w_]+)\]\([^)]*\)\s*\|\s*(.+?)\s*\|\s*$');
  for (final line in src) {
    final m = re.firstMatch(line);
    if (m != null) {
      rows.add((m.group(1)!, md.markdownToHtml(m.group(2)!, inlineOnly: true)));
    }
  }
  return rows;
}

Component _eyebrow(String text) => p(classes: 'eyebrow', [.text(text)]);

Component _codeFile(String name, String lang, String source) {
  return figure(classes: 'code-file', [
    figcaption(classes: 'code-file-name', [
      span(classes: 'code-dot', attributes: {'aria-hidden': 'true'}, []),
      .text(name),
    ]),
    pre(attributes: {'data-lang': lang}, [
      code([RawText(highlight(source, lang).replaceAll('\n', '&#10;'))]),
    ]),
  ]);
}

Component _copyBlock(String id, String label, String lang, String text) {
  return div(classes: 'copy-block', [
    div(classes: 'copy-block-head', [
      span(classes: 'copy-block-label', [.text(label)]),
      button(
        type: ButtonType.button,
        classes: 'copy-btn',
        attributes: {'data-copy-target': id, 'aria-label': 'Copy $label'},
        [span(classes: 'copy-btn-text', [.text('Copy')])],
      ),
    ]),
    pre(id: id, attributes: {'data-lang': lang}, [
      code([RawText(highlight(text, lang).replaceAll('\n', '&#10;'))]),
    ]),
  ]);
}

class HomePage extends StatelessComponent {
  const HomePage({super.key});

  @override
  Component build(BuildContext context) {
    final packages = _packageRows();
    final entryCards = [
      ('guides', 'Guides', 'Task-oriented walkthroughs: first app, backends, testing.'),
      ('packages', 'Packages', 'The documentation of record for each of the eight Dart packages.'),
      ('examples', 'Examples', 'Working todo apps on the interpreter, AOT and Skia backends.'),
    ];

    return Component.fragment([
      siteHeader(active: 'home'),
      main_(id: 'main', classes: 'landing', [
        // ── Hero ──────────────────────────────────────────────
        section(classes: 'hero', attributes: {'aria-labelledby': 'hero-title'}, [
          div(classes: 'container hero-grid', [
            div(classes: 'hero-copy', [
              div(classes: 'hero-mark', [
                img(src: 'images/logo.svg', alt: '', width: 56, height: 56),
                span(classes: 'hero-chip', [
                  span(classes: 'mint-bar', attributes: {'aria-hidden': 'true'}, []),
                  .text('Open source · MIT'),
                ]),
              ]),
              h1(id: 'hero-title', [.text('Slint UI toolkit ↔ Flutter')]),
              p(classes: 'hero-sub', [
                .text('One typed API over interpreter and AOT backends — plus headless and on-device UI testing.'),
              ]),
              div(classes: 'hero-actions', [
                a(href: 'guides/getting-started/', classes: 'btn btn-filled', [
                  .text('Get started'),
                  RawText(iconArrow),
                ]),
                a(href: githubUrl, classes: 'btn btn-outlined', [
                  RawText(iconGithub),
                  .text('GitHub'),
                ]),
              ]),
              p(classes: 'hero-meta', [
                .text('Flutter stable · Dart 3.13+ · Rust via rustup'),
              ]),
            ]),
            div(classes: 'hero-code', attributes: {'aria-label': 'Code sample'}, [
              _codeFile('ui/hello.slint', 'slint', _helloSlint),
              _codeFile('lib/main.dart', 'dart', _mainDart),
            ]),
          ]),
        ]),

        // ── Features ─────────────────────────────────────────
        section(classes: 'section', attributes: {'aria-labelledby': 'features-title'}, [
          div(classes: 'container', [
            div(classes: 'section-head', [
              _eyebrow('Why slint_dart'),
              h2(id: 'features-title', [.text('One .slint file, two backends, one typed API')]),
            ]),
            div(classes: 'feature-grid', [
              for (final (title, body, icon) in _features)
                div(classes: 'feature', [
                  RawText(
                    '<svg class="feature-icon" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">$icon</svg>',
                  ),
                  h3([.text(title)]),
                  p([RawText(body)]),
                ]),
            ]),
          ]),
        ]),

        // ── Platforms & packages ─────────────────────────────
        section(classes: 'section section-alt', attributes: {'aria-labelledby': 'packages-title'}, [
          div(classes: 'container split', [
            div(classes: 'split-aside', [
              _eyebrow('Platforms'),
              h2(id: 'packages-title', [.text('Where it runs, what you install')]),
              p(classes: 'section-sub', [
                .text(
                  'The hooks derive everything per platform from the build input — Rust target triple, Android NDK, Apple deployment targets — so no platform-specific configuration lives in the app.',
                ),
              ]),
              ul(classes: 'platforms', [
                for (final name in ['macOS', 'iOS', 'Android'])
                  li(classes: 'platform is-ok', [
                    span(classes: 'platform-name', [.text(name)]),
                    span(classes: 'platform-status', [.text('Builds and runs')]),
                  ]),
                for (final name in ['Linux', 'Windows'])
                  li(classes: 'platform', [
                    span(classes: 'platform-name', [.text(name)]),
                    span(classes: 'platform-status', [.text('Mapped, untested')]),
                  ]),
              ]),
            ]),
            div(classes: 'package-list', attributes: {'role': 'list', 'aria-label': 'Packages'}, [
              for (final (name, role) in packages)
                a(href: 'packages/$name/', classes: 'package-row', attributes: {'role': 'listitem'}, [
                  code(classes: 'package-name', [.text(name)]),
                  span(classes: 'package-role', [RawText(role)]),
                  RawText(iconArrow),
                ]),
            ]),
          ]),
        ]),

        // ── Install ──────────────────────────────────────────
        section(classes: 'section', attributes: {'aria-labelledby': 'install-title'}, [
          div(classes: 'container split', [
            div(classes: 'split-aside', [
              _eyebrow('Install'),
              h2(id: 'install-title', [.text('Add the packages, generate the wrappers')]),
              p(classes: 'section-sub', [
                .text('Add the dependencies to your app’s pubspec.yaml, then run build_runner after every .slint edit. '),
                a(href: 'guides/getting-started/', [.text('The getting started guide')]),
                .text(' covers build.yaml and the native hooks.'),
              ]),
            ]),
            div(classes: 'install-steps', [
              _copyBlock('install-pubspec', 'pubspec.yaml', 'yaml', _pubspec),
              _copyBlock('install-generate', 'Terminal', 'bash', _generate),
            ]),
          ]),
        ]),

        // ── Docs entry ───────────────────────────────────────
        section(classes: 'section section-last', attributes: {'aria-labelledby': 'docs-title'}, [
          div(classes: 'container', [
            div(classes: 'section-head', [
              _eyebrow('Documentation'),
              h2(id: 'docs-title', [.text('Start reading')]),
            ]),
            div(classes: 'entry-grid', [
              for (final (key, title, sub) in entryCards)
                div(classes: 'entry-card', [
                  a(href: '$key/', classes: 'entry-card-link', [
                    h3([.text(title), RawText(iconArrow)]),
                  ]),
                  p([.text(sub)]),
                  ul(classes: 'entry-pages', [
                    for (final page in docPages.where((pg) => pg.section == key && pg.route != '/$key').take(4))
                      li([
                        a(href: hrefOf(page.route), [.text(page.title)]),
                      ]),
                  ]),
                ]),
            ]),
          ]),
        ]),
      ]),
      siteFooter(),
    ]);
  }
}

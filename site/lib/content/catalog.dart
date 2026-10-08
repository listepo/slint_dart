/// Docs catalog, generated at build time from the Markdown sources.
///
/// Single source of truth: every `*.md` under
///   * `site/web/content/` (the docs site content), and
///   * the repository-level `docs/` folder
/// becomes exactly one page. Nothing is listed by hand — add a file and it
/// gets a route, a sidebar entry and prev/next links on the next build.
///
/// Routes must not end with `/` (jaspr_router assertion), except `/`.
library;

import 'dart:io';

/// A Markdown source tree mounted under a route prefix.
class DocSource {
  const DocSource({
    required this.dir,
    required this.repoPath,
    required this.routePrefix,
    required this.indexRoute,
  });

  /// Directory relative to the build CWD (`site/`).
  final String dir;

  /// Same directory relative to the repository root (for GitHub links).
  final String repoPath;

  /// Route prefix, e.g. `''` or `/docs`.
  final String routePrefix;

  /// Route used for the tree's top-level `index.md`.
  final String indexRoute;
}

const docSources = <DocSource>[
  // content/index.md used to be the home page; the landing page replaced it,
  // so its full text lives on at /overview instead of being dropped.
  DocSource(dir: 'web/content', repoPath: 'site/web/content', routePrefix: '', indexRoute: '/overview'),
  DocSource(dir: '../docs', repoPath: 'docs', routePrefix: '/docs', indexRoute: '/docs'),
];

class DocPage {
  const DocPage({
    required this.route,
    required this.file,
    required this.repoFile,
    required this.title,
    required this.section,
  });

  /// Site route, e.g. `/guides/testing`.
  final String route;

  /// Source path relative to the build CWD (`site/`), e.g. `web/content/guides/testing.md`.
  final String file;

  /// Source path relative to the repository root, e.g. `site/web/content/guides/testing.md`.
  final String repoFile;

  final String title;

  /// Sidebar section key (see [navSections]).
  final String section;
}

/// Sidebar sections in display order: key → heading.
const navSections = <(String, String)>[
  ('guides', 'Guides'),
  ('packages', 'Packages'),
  ('examples', 'Examples'),
  ('project', 'Project'),
  ('docs', 'Maintainer docs'),
];

/// Preferred order inside a section; files not listed follow alphabetically.
const _order = <String, int>{
  '/guides': 0,
  '/guides/getting-started': 1,
  '/guides/backends': 2,
  '/guides/testing': 3,
  '/packages': 0,
  '/packages/slint': 1,
  '/packages/slint_generator': 2,
  '/packages/slint_interpreter': 3,
  '/packages/slint_compiler': 4,
  '/packages/slint_build': 5,
  '/packages/slint_skia': 6,
  '/packages/slint_testing': 7,
  '/packages/slint_patrol': 8,
  '/examples': 0,
  '/overview': 0,
  '/contributing': 1,
  '/docs': 0,
};

/// Title overrides where neither an H1 nor the file name reads well.
const _titles = <String, String>{
  '/overview': 'Project overview',
  '/guides': 'Guides',
  '/packages': 'Packages',
  '/examples': 'Examples',
  '/examples/todo_skia': 'Todo Skia',
};

List<DocPage>? _cache;

/// Every docs page, in sidebar order.
List<DocPage> get docPages => _cache ??= _scan();

List<DocPage> _scan() {
  final pages = <DocPage>[];
  for (final src in docSources) {
    final root = Directory(src.dir);
    if (!root.existsSync()) continue;
    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md') && !_base(f.path).startsWith('.'))
        .toList();
    for (final f in files) {
      final rel = _rel(f.path, root.path);
      final route = routeForSource(src, rel);
      pages.add(DocPage(
        route: route,
        file: '${src.dir}/$rel',
        repoFile: '${src.repoPath}/$rel',
        title: _titles[route] ?? _titleOf(f, rel),
        section: _sectionOf(src, route),
      ));
    }
  }
  int sectionIdx(DocPage p) => navSections.indexWhere((s) => s.$1 == p.section);
  pages.sort((a, b) {
    final s = sectionIdx(a).compareTo(sectionIdx(b));
    if (s != 0) return s;
    final o = (_order[a.route] ?? 100).compareTo(_order[b.route] ?? 100);
    if (o != 0) return o;
    return a.route.compareTo(b.route);
  });
  return pages;
}

/// `guides/index.md` → `/guides`, `guides/testing.md` → `/guides/testing`.
String routeForSource(DocSource src, String rel) {
  var path = rel.substring(0, rel.length - 3); // strip .md
  if (path == 'index') return src.indexRoute;
  if (path.endsWith('/index')) path = path.substring(0, path.length - 6);
  return '${src.routePrefix}/$path';
}

String _sectionOf(DocSource src, String route) {
  if (src.routePrefix == '/docs') return 'docs';
  final first = route.split('/').where((s) => s.isNotEmpty).first;
  return const {'guides', 'packages', 'examples'}.contains(first) ? first : 'project';
}

String _titleOf(File f, String rel) {
  var inFence = false;
  for (final line in f.readAsLinesSync()) {
    if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) inFence = !inFence;
    if (inFence) continue;
    final m = RegExp(r'^#\s+(.+?)\s*#*\s*$').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  var name = _base(rel).replaceAll('.md', '');
  if (name == 'index') {
    final parts = rel.split('/');
    name = parts.length > 1 ? parts[parts.length - 2] : 'Overview';
  }
  // Package names stay verbatim (`slint_build`); prose names get sentence case.
  if (rel.startsWith('packages/')) return name;
  final words = name.replaceAll(RegExp(r'[-_]'), ' ');
  return words[0].toUpperCase() + words.substring(1);
}

String _base(String path) => path.split(Platform.pathSeparator).last.split('/').last;

String _rel(String path, String root) {
  var r = path.substring(root.length).replaceAll(Platform.pathSeparator, '/');
  while (r.startsWith('/')) {
    r = r.substring(1);
  }
  return r;
}

DocPage? pageForRoute(String route) {
  for (final p in docPages) {
    if (p.route == route) return p;
  }
  return null;
}

/// Source repo path (e.g. `site/web/content/guides/testing.md`) → page.
DocPage? pageForRepoFile(String repoFile) {
  for (final p in docPages) {
    if (p.repoFile == repoFile) return p;
  }
  return null;
}

/// Base-relative href for a route under `<base href="/slint_dart/">`.
/// Always ends in `/` so GitHub Pages serves `route/index.html` without a redirect.
String hrefOf(String route) {
  if (route == '/') return './';
  final r = route.startsWith('/') ? route.substring(1) : route;
  return r.endsWith('/') ? r : '$r/';
}

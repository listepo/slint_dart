import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../content/catalog.dart';

export '../content/catalog.dart' show hrefOf;

const githubUrl = 'https://github.com/listepo/slint_dart';

const _iconSun = '''
<svg class="theme-toggle-icon icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" aria-hidden="true">
  <circle cx="12" cy="12" r="4"></circle>
  <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"></path>
</svg>''';

const _iconMoon = '''
<svg class="theme-toggle-icon icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <path d="M21 14.5A8.5 8.5 0 1 1 9.5 3a7 7 0 0 0 11.5 11.5z"></path>
</svg>''';

const _iconSystem = '''
<svg class="theme-toggle-icon icon-system" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <rect x="3" y="4" width="18" height="12" rx="2"></rect>
  <path d="M8 20h8M12 16v4"></path>
</svg>''';

const iconGithub = '''
<svg class="icon" viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
  <path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.04-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.41-2.69 5.38-5.25 5.67.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5z"/>
</svg>''';

const iconArrow = '''
<svg class="icon icon-arrow" viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  <path d="M3 8h10M9 4l4 4-4 4"/>
</svg>''';

/// Wordmark: `slint_dart` with the underscore in primary (matches logo-wordmark.svg).
Component wordmark() => span(classes: 'wordmark', [
      .text('slint'),
      span(classes: 'wordmark-us', [.text('_')]),
      .text('dart'),
    ]);

String sectionTitle(String key) {
  for (final (k, t) in navSections) {
    if (k == key) return t;
  }
  return 'Docs';
}

Component siteHeader({required String active}) {
  final links = [
    ('Guides', 'guides/', 'guides'),
    ('Packages', 'packages/', 'packages'),
    ('Examples', 'examples/', 'examples'),
    ('Contributing', 'contributing/', 'project'),
  ];
  return Component.fragment([
    a(href: '#main', classes: 'skip-link', [.text('Skip to content')]),
    header(classes: 'site-header', [
      div(classes: 'site-header-inner', [
        a(href: './', classes: 'brand', attributes: {'aria-label': 'slint_dart home'}, [
          img(src: 'images/logo.svg', alt: '', width: 28, height: 28),
          wordmark(),
        ]),
        nav(classes: 'nav', attributes: {'aria-label': 'Primary'}, [
          for (final (label, href, key) in links)
            a(
              href: href,
              classes: active == key ? 'is-active' : null,
              attributes: active == key ? {'aria-current': 'true'} : null,
              [.text(label)],
            ),
        ]),
        div(classes: 'header-actions', [
          a(href: githubUrl, classes: 'icon-btn', attributes: {'aria-label': 'slint_dart on GitHub'}, [
            RawText(iconGithub),
          ]),
          button(
            type: ButtonType.button,
            id: 'theme-toggle',
            classes: 'icon-btn theme-toggle',
            attributes: {'data-theme': 'system', 'aria-label': 'Theme: system (follows OS)'},
            [RawText(_iconSun), RawText(_iconMoon), RawText(_iconSystem)],
          ),
        ]),
      ]),
    ]),
  ]);
}

Component siteFooter() {
  return footer(classes: 'site-footer', [
    div(classes: 'site-footer-inner', [
      div(classes: 'footer-brand', [
        a(href: './', classes: 'brand', attributes: {'aria-label': 'slint_dart home'}, [
          img(src: 'images/logo.svg', alt: '', width: 24, height: 24),
          wordmark(),
        ]),
        p(classes: 'footer-note', [
          .text('MIT licensed. Built on '),
          a(href: 'https://slint.dev', [.text('Slint')]),
          .text(', the UI toolkit by SixtyFPS GmbH, available under its own licenses.'),
        ]),
      ]),
      nav(classes: 'footer-links', attributes: {'aria-label': 'Footer'}, [
        div([
          p(classes: 'footer-h', [.text('Docs')]),
          a(href: 'guides/getting-started/', [.text('Getting started')]),
          a(href: 'guides/', [.text('Guides')]),
          a(href: 'packages/', [.text('Packages')]),
          a(href: 'examples/', [.text('Examples')]),
        ]),
        div([
          p(classes: 'footer-h', [.text('Project')]),
          a(href: githubUrl, [.text('GitHub')]),
          a(href: '$githubUrl#readme', [.text('README')]),
          a(href: 'contributing/', [.text('Contributing')]),
          a(href: 'overview/', [.text('Project overview')]),
        ]),
      ]),
    ]),
  ]);
}

List<Component> _sidebarSections(String currentRoute) {
  return [
    for (final (key, title) in navSections)
      if (docPages.any((pg) => pg.section == key))
        div(classes: 'side-section', [
          p(classes: 'side-h', [.text(title)]),
          ul([
            for (final pg in docPages.where((pg) => pg.section == key))
              li([
                a(
                  href: hrefOf(pg.route),
                  classes: currentRoute == pg.route ? 'is-active' : null,
                  attributes: currentRoute == pg.route ? {'aria-current': 'page'} : null,
                  [.text(pg.route == '/$key' ? 'Overview' : pg.title)],
                ),
              ]),
          ]),
        ]),
  ];
}

/// Desktop sidebar — generated from the catalog, so it always lists every page.
Component docsSidebar({required String currentRoute}) {
  return aside(classes: 'sidebar', attributes: {'aria-label': 'Documentation'}, [
    nav(classes: 'sidebar-inner', attributes: {'aria-label': 'All docs pages'}, _sidebarSections(currentRoute)),
  ]);
}

/// Narrow screens: the same navigation in a disclosure above the content.
Component mobileDocsNav({required String currentRoute}) {
  final current = pageForRoute(currentRoute);
  return details(classes: 'mobile-docs-nav', [
    summary([
      span(classes: 'mdn-label', [.text('Browse docs')]),
      span(classes: 'mdn-current', [.text(current?.title ?? '')]),
    ]),
    nav(classes: 'mdn-body', attributes: {'aria-label': 'All docs pages (mobile)'}, _sidebarSections(currentRoute)),
  ]);
}

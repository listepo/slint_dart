import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:markdown/markdown.dart' as md;

import '../pages/shell.dart';
import 'catalog.dart';
import 'highlight.dart';

const repoBlobBase = 'https://github.com/listepo/slint_dart/blob/main/';

/// Rendered page body plus the H2 outline used for "On this page".
class RenderedDoc {
  RenderedDoc(this.html, this.outline, {required this.hasH1});
  final String html;
  final List<(String id, String text)> outline;
  final bool hasH1;
}

RenderedDoc renderDoc(DocPage page) {
  // jaspr build CWD is site/
  final source = File(page.file).readAsStringSync();
  final doc = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: const [md.HeaderWithIdSyntax(), md.SetextHeaderWithIdSyntax()],
  );
  final nodes = doc.parseLines(source.replaceAll('\r\n', '\n').split('\n'));
  final outline = <(String, String)>[];
  var hasH1 = false;
  _transform(nodes, page, outline, (v) => hasH1 = hasH1 || v);
  return RenderedDoc(preserveNewlines(md.renderToHtml(nodes)), outline, hasH1: hasH1);
}

void _transform(List<md.Node> nodes, DocPage page, List<(String, String)> outline, void Function(bool) sawH1) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! md.Element) continue;
    switch (node.tag) {
      case 'h1':
        sawH1(true);
      case 'h2':
        final id = node.generatedId;
        if (id != null) outline.add((id, node.textContent));
      case 'a':
        final href = node.attributes['href'];
        if (href != null) node.attributes['href'] = rewriteHref(href, page);
      case 'input':
        // GFM task lists: read-only checkboxes.
        node.attributes['disabled'] = '';
        final checked = node.attributes.containsKey('checked');
        node.attributes['aria-label'] = checked ? 'Done' : 'Not done';
      case 'img':
        final src = node.attributes['src'];
        if (src != null) node.attributes['src'] = rewriteHref(src, page, asset: true);
      case 'table':
        // Horizontal scroll on narrow screens without breaking the table model.
        _transform(node.children ?? [], page, outline, sawH1);
        nodes[i] = md.Element('div', [node])..attributes['class'] = 'table-wrap';
        continue;
      case 'pre':
        final code = node.children?.whereType<md.Element>().firstOrNull;
        if (code != null && code.tag == 'code') {
          final lang = code.attributes['class']?.replaceFirst('language-', '');
          final raw = unescapeHtml(code.textContent);
          code.children
            ?..clear()
            ..add(md.Text(highlight(raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw, lang)));
          if (lang != null && lang.isNotEmpty) node.attributes['data-lang'] = lang;
        }
        continue;
    }
    final kids = node.children;
    if (kids != null) _transform(kids, page, outline, sawH1);
  }
}

/// Rewrites a Markdown link so it works under `<base href="/slint_dart/">`:
///  * `#frag`                  → `<this page>/#frag`
///  * `/guides/testing[.md]`   → `guides/testing/`   (site-absolute routes)
///  * `../docs/x.md`, `x.md`   → the route generated for that source file
///  * other repo-relative paths → the file on GitHub
///  * `https:`, `mailto:` …    → unchanged
String rewriteHref(String href, DocPage page, {bool asset = false}) {
  if (href.isEmpty) return href;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(href) || href.startsWith('//')) return href;
  final hashAt = href.indexOf('#');
  final path = hashAt < 0 ? href : href.substring(0, hashAt);
  final frag = hashAt < 0 ? '' : href.substring(hashAt);
  if (path.isEmpty) return '${hrefOf(page.route)}$frag';

  if (path.startsWith('/')) {
    var route = path.replaceAll(RegExp(r'/+$'), '');
    if (route.endsWith('.md')) route = route.substring(0, route.length - 3);
    if (route.endsWith('/index')) route = route.substring(0, route.length - 6);
    if (route.isEmpty) return './$frag';
    if (asset) return route.substring(1);
    return '${hrefOf(route)}$frag';
  }

  // Relative: resolve against the source file's directory in the repo.
  final dir = page.repoFile.contains('/') ? page.repoFile.substring(0, page.repoFile.lastIndexOf('/')) : '';
  final resolved = _normalize('$dir/$path');
  final target = pageForRepoFile(resolved) ??
      pageForRepoFile('$resolved.md') ??
      pageForRepoFile('${resolved.replaceAll(RegExp(r'/+$'), '')}/index.md');
  if (target != null) return '${hrefOf(target.route)}$frag';
  if (resolved.startsWith('../')) return href; // outside the repo: leave as written
  return '$repoBlobBase$resolved$frag';
}

String _normalize(String path) {
  final out = <String>[];
  for (final seg in path.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else {
        out.add('..');
      }
    } else {
      out.add(seg);
    }
  }
  return out.join('/');
}

class MarkdownDocPage extends StatelessComponent {
  const MarkdownDocPage({required this.route, super.key});

  final String route;

  @override
  Component build(BuildContext context) {
    final page = pageForRoute(route)!;
    final rendered = renderDoc(page);
    final idx = docPages.indexOf(page);
    final prev = idx > 0 ? docPages[idx - 1] : null;
    final next = idx < docPages.length - 1 ? docPages[idx + 1] : null;

    return Component.fragment([
      Document.head(title: '${page.title} — slint_dart'),
      siteHeader(active: page.section),
      div(classes: 'docs-shell', [
        docsSidebar(currentRoute: route),
        main_(id: 'main', classes: 'doc-main', [
          mobileDocsNav(currentRoute: route),
          nav(classes: 'breadcrumbs', attributes: {'aria-label': 'Breadcrumb'}, [
            a(href: './', [.text('Home')]),
            span(classes: 'sep', attributes: {'aria-hidden': 'true'}, [.text('/')]),
            span([.text(sectionTitle(page.section))]),
          ]),
          article(classes: 'doc-body prose', [
            if (!rendered.hasH1) h1([.text(page.title)]),
            RawText(rendered.html),
          ]),
          div(classes: 'doc-meta', [
            a(href: '$repoBlobBase${page.repoFile}', classes: 'doc-source', [
              .text('Source: '),
              code([.text(page.repoFile)]),
            ]),
          ]),
          nav(classes: 'pager', attributes: {'aria-label': 'Previous and next page'}, [
            if (prev != null)
              a(href: hrefOf(prev.route), classes: 'pager-link pager-prev', [
                span(classes: 'pager-label', [.text('Previous')]),
                span(classes: 'pager-title', [.text(prev.title)]),
              ])
            else
              span([]),
            if (next != null)
              a(href: hrefOf(next.route), classes: 'pager-link pager-next', [
                span(classes: 'pager-label', [.text('Next')]),
                span(classes: 'pager-title', [.text(next.title)]),
              ]),
          ]),
        ]),
        if (rendered.outline.length > 1)
          aside(classes: 'toc', attributes: {'aria-label': 'On this page'}, [
            p(classes: 'toc-title', [.text('On this page')]),
            ul([
              for (final (id, text) in rendered.outline)
                li([
                  a(href: '${hrefOf(route)}#$id', [.text(text)]),
                ]),
            ]),
          ]),
      ]),
      siteFooter(),
    ]);
  }
}

#!/usr/bin/env python3
"""Verify the built docs site against its Markdown sources.

Checks, after `jaspr build` (run from site/):
  1. every docs source file (site/web/content/**/*.md and docs/**/*.md) has
     exactly one built HTML page (matched via the page's "Source:" footer);
  2. each page's headings match the source headings, and every word of the
     source text appears on the page (multiset coverage, so nothing dropped);
  3. the sidebar on every docs page links to every docs page;
  4. zero broken internal links: every href/src resolves to a built file
     under the /slint_dart/ base, and every #fragment exists on its target.

Usage: python3 tool/verify_site.py [build_dir] [--report out.md]
Exit code is non-zero on any failure. Standard library only.
"""
from __future__ import annotations

import html
import re
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

SITE = Path(__file__).resolve().parent.parent
REPO = SITE.parent
SOURCES = [SITE / "web" / "content", REPO / "docs"]
BASE = "/slint_dart/"
ORIGIN = "https://listepo.github.io"


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.base = None
        self.links: list[tuple[str, str]] = []  # (attr, value)
        self.ids: set[str] = set()
        self.source: str | None = None
        self.headings: list[str] = []
        self.sidebar: list[str] = []
        self._stack: list[str] = []
        self._in_article = 0
        self._in_sidebar = 0
        self._in_source = 0
        self._heading: list[str] | None = None
        self._skip = 0  # inside a copy button
        self.article_text: list[str] = []

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "base":
            self.base = a.get("href")
        if a.get("id"):
            self.ids.add(a["id"])
        if tag == "a" and a.get("name"):
            self.ids.add(a["name"])
        for attr in ("href", "src"):
            if a.get(attr) is not None and tag in {"a", "img", "link", "script", "source"}:
                self.links.append((f"{tag}[{attr}]", a[attr]))
        cls = (a.get("class") or "").split()
        if tag == "article" and "doc-body" in cls:
            self._in_article = 1
        if tag == "aside" and "sidebar" in cls:
            self._in_sidebar = 1
        if tag == "a" and "doc-source" in cls:
            self._in_source = 1
            self.source = ""
        if self._in_sidebar and tag == "a":
            self.sidebar.append(a.get("href", ""))
        if self._in_article and re.fullmatch(r"h[1-6]", tag):
            self._heading = []
        if tag == "button" and "copy-btn" in cls:
            self._skip = 1

    def handle_endtag(self, tag):
        if self._heading is not None and re.fullmatch(r"h[1-6]", tag):
            self.headings.append(norm_ws("".join(self._heading)))
            self._heading = None
        if tag == "article":
            self._in_article = 0
        if tag == "aside":
            self._in_sidebar = 0
        if tag == "a":
            self._in_source = 0
        if tag == "button":
            self._skip = 0

    def handle_data(self, data):
        if self._in_source and self.source is not None:
            self.source += data
        if self._in_article and not self._skip:
            self.article_text.append(data)
            if self._heading is not None:
                self._heading.append(data)


def norm_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def md_headings(src: str) -> list[str]:
    out, fence = [], False
    for line in src.splitlines():
        if re.match(r"^\s*(```|~~~)", line):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if m:
            out.append(norm_ws(md_inline_text(m.group(1))))
    return out


def md_inline_text(s: str) -> str:
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)  # links/images -> text
    s = re.sub(r"<(https?://[^>]+)>", r"\1", s)  # autolinks keep their text
    s = s.replace("`", "")
    s = re.sub(r"(\*\*|__|\*|~~)", "", s)
    return html.unescape(s)


def words(s: str) -> Counter:
    return Counter(re.findall(r"[A-Za-z0-9]+", s))


def page_files(build: Path) -> list[Path]:
    return sorted(build.rglob("*.html"))


def resolve(build: Path, page_url: str, base: str, ref: str) -> tuple[Path | None, str, str]:
    """Returns (file, fragment, absolute URL) for an internal ref; file None if external."""
    absolute = urljoin(urljoin(ORIGIN + page_url, base), ref)
    u = urlparse(absolute)
    if f"{u.scheme}://{u.netloc}" != ORIGIN:
        return None, "", absolute
    path = unquote(u.path)
    if not path.startswith(BASE):
        return build / "__outside_base__", u.fragment, absolute
    rel = path[len(BASE):]
    target = build / rel
    if rel == "" or rel.endswith("/"):
        target = target / "index.html"
    elif target.is_dir():
        target = target / "index.html"
    return target, u.fragment, absolute


def main() -> int:
    args = sys.argv[1:]
    report_path = None
    if "--report" in args:
        i = args.index("--report")
        report_path = Path(args[i + 1])
        del args[i : i + 2]
    build = Path(args[0]) if args else SITE / "build" / "jaspr"
    failures: list[str] = []
    lines: list[str] = []

    parsed: dict[Path, Page] = {}
    for f in page_files(build):
        p = Page()
        p.feed(f.read_text(encoding="utf-8"))
        parsed[f] = p

    def url_of(f: Path) -> str:
        rel = f.relative_to(build).as_posix()
        return BASE + (rel[: -len("index.html")] if rel.endswith("index.html") else rel)

    # 1. Source files -> pages
    by_source = {}
    for f, p in parsed.items():
        if p.source:
            src = norm_ws(p.source).replace("Source: ", "")
            if src in by_source:
                failures.append(f"duplicate page for {src}: {url_of(by_source[src])} and {url_of(f)}")
            by_source[src] = f
    sources = []
    for root in SOURCES:
        if root.is_dir():
            sources += sorted(x for x in root.rglob("*.md") if not x.name.startswith("."))
    lines.append("| # | Source | Route | Headings | Word coverage |")
    lines.append("|---|---|---|---|---|")
    doc_urls = set()
    for n, src in enumerate(sources, 1):
        rel = src.relative_to(REPO).as_posix()
        f = by_source.get(rel)
        if f is None:
            failures.append(f"no built page for {rel}")
            lines.append(f"| {n} | `{rel}` | MISSING | – | – |")
            continue
        url = url_of(f)
        doc_urls.add(url)
        p = parsed[f]
        text = src.read_text(encoding="utf-8")
        want_h = md_headings(text)
        got_h = [h for h in p.headings]
        # A page without an H1 in its source gets the catalog title as H1.
        if got_h and (not want_h or got_h[0] != want_h[0]) and len(got_h) == len(want_h) + 1:
            got_h = got_h[1:]
        h_ok = got_h == want_h
        if not h_ok:
            failures.append(f"{rel}: headings differ\n    source: {want_h}\n    page:   {got_h}")
        body = re.sub(r"^(\s*)(```|~~~)\s*[\w+-]*\s*$", r"\1\2", text, flags=re.M)  # fence info (```bash) renders as a label, not text
        body = re.sub(r"^(\s*)\d+\.\s", r"\1", body, flags=re.M)  # ordered-list numbers render as <ol> markers
        body = re.sub(r"^(\s*[-*+]\s+)\[[ xX]\]", r"\1", body, flags=re.M)  # task-list markers render as checkboxes
        src_words = words(md_inline_text(re.sub(r"\]\([^)]*\)", "]", body)))
        page_words = words(html.unescape("".join(p.article_text)))
        missing = src_words - page_words
        total = sum(src_words.values())
        cov = 100.0 * (total - sum(missing.values())) / max(total, 1)
        if missing:
            failures.append(f"{rel}: {sum(missing.values())} source word(s) missing on page: {dict(list(missing.items())[:12])}")
        lines.append(
            f"| {n} | `{rel}` | `{url}` | {len(want_h)} {'✓' if h_ok else '✗'} | {cov:.1f}% ({total} words) |"
        )

    # 3. Sidebar coverage
    for f, p in parsed.items():
        if not p.source:
            continue
        base = p.base or BASE
        side = set()
        for href in p.sidebar:
            _, _, absu = resolve(build, url_of(f), base, href)
            side.add(urlparse(absu).path)
        missing_nav = doc_urls - side
        if missing_nav:
            failures.append(f"{url_of(f)}: sidebar misses {sorted(missing_nav)}")

    # 4. Link check
    checked = external = 0
    broken: list[str] = []
    for f, p in parsed.items():
        base = p.base or BASE
        for attr, ref in p.links:
            if ref.startswith(("mailto:", "tel:", "javascript:", "data:")):
                continue
            target, frag, absu = resolve(build, url_of(f), base, ref)
            if target is None:
                external += 1
                continue
            checked += 1
            if not target.exists():
                broken.append(f"{url_of(f)}: {attr}={ref!r} -> {absu} (no file)")
                continue
            if frag and target.suffix == ".html":
                tp = parsed.get(target)
                if tp is None or unquote(frag) not in tp.ids:
                    broken.append(f"{url_of(f)}: {attr}={ref!r} -> missing #{frag}")
    failures += broken

    summary = [
        f"Docs source files: {len(sources)}",
        f"Built docs pages matched: {len(doc_urls)}",
        f"HTML pages in build (incl. landing): {len(parsed)}",
        f"Internal links/assets checked: {checked}, broken: {len(broken)} (external skipped: {external})",
    ]
    out = "\n".join(summary) + "\n\n" + "\n".join(lines) + "\n"
    if failures:
        out += "\nFAILURES:\n" + "\n".join(f"- {x}" for x in failures) + "\n"
    else:
        out += "\nAll checks passed.\n"
    print(out)
    if report_path:
        report_path.write_text(out, encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

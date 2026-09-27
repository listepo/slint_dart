# slint_dart docs site

Static docs site built with [Jaspr](https://docs.jaspr.site/) (Dart SSG).

```bash
cd site
dart pub get
dart pub global activate jaspr_cli
jaspr build
python3 tool/verify_site.py build/jaspr   # pages, content and link check
```

Output: `build/jaspr/`. Project Pages base path: `/slint_dart/`.
To preview locally with the base path:

```bash
mkdir -p /tmp/sd && ln -sfn "$PWD/build/jaspr" /tmp/sd/slint_dart
cd /tmp/sd && python3 -m http.server 8000   # open http://localhost:8000/slint_dart/
```

## Content

Pages are generated at build time — nothing is listed by hand
(`lib/content/catalog.dart`):

| Source | Route |
|---|---|
| `site/web/content/<path>.md` | `/<path>` (`<dir>/index.md` → `/<dir>`) |
| `site/web/content/index.md` | `/overview` (the landing page is `lib/pages/home.dart`) |
| `docs/<path>.md` (repo root) | `/docs/<path>` |

Add a Markdown file and it gets a route, a sidebar entry and prev/next links.
Links are rewritten for the base path: site-absolute (`/guides/testing`),
relative `.md` links and `#anchors` resolve to site routes; other
repo-relative paths point at the file on GitHub.

`tool/verify_site.py` (also run in the Pages workflow) checks that every
source file has a page, that headings and text match the source, that every
sidebar lists every page, and that no internal link or anchor is broken.

## Design

Brand tokens (`web/styles/tokens.css`) follow the slint_dart brand pack:
Material 3 structure × Apple HIG precision, primary `#0B57D0`, mint
`#006B5F` / `#5CE1C8`, double-stroke focus ring. Light and dark themes follow
`prefers-color-scheme`; the header toggle cycles system → light → dark.

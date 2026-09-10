#!/usr/bin/env zsh
# Regenerate the Hugo docs site content from the READMEs (documentation of
# record). Run from the repo root: `zsh site/sync.sh`.
#
# Layout: every package README becomes site/content/packages/<pkg>.md,
# examples land under site/content/examples/, guides under
# site/content/guides/, and CONTRIBUTING.md becomes the contributing page.
# Front matter carries the title (first `# ` line), description (first
# non-heading prose line after it), and weight. Section `_index.md` pages set
# `cascade: {type: docs}` for Hextra sidebars — sync does not need to emit
# `type`. The body is the README with that first `# ` heading stripped (the
# page title renders from front matter) and intra-repo `.md` links rewritten
# to Hugo relrefs.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTENT="$REPO/site/content"
PACKAGES=(slint slint_build slint_compiler slint_generator slint_interpreter slint_patrol slint_skia slint_testing)
EXAMPLES=(todo todo_shared todo_skia)

mkdir -p "$CONTENT/packages" "$CONTENT/guides" "$CONTENT/examples"

rewrite_links() {
  # ../slint_patrol -> relref to the sibling package page; examples/todo ->
  # relref to the example page. Order matters (longer prefixes first).
  sed -E \
    -e 's#\(\.\./(slint_build|slint_compiler|slint_generator|slint_interpreter|slint_patrol|slint_skia|slint_testing|slint)(/[^)]*)?\)#({{< relref "packages/\1" >}})#g' \
    -e 's#\(examples/(todo_skia|todo_shared|todo)(/[^)]*)?\)#({{< relref "examples/\2" >}})#g'
}

page_from_readme() {
  local src="$1" dest="$2" weight="$3"
  local title desc
  title="$(sed -n 's/^# //p' "$src" | head -n 1)"
  # First prose line: skip blanks, headings, lists, fenced code (incl. body), and wrapped list continuations.
  desc="$(awk 'NR>1 {
    if ($0 ~ /^```/) { fence = !fence; next }
    if (fence) next
    if ($0 ~ /^[[:space:]]*$/) next
    if ($0 ~ /^#/ || $0 ~ /^[-*] /) next
    if ($0 ~ /^[[:space:]]/) next
    print; exit
  }' "$src")"
  {
    printf -- '---\ntitle: "%s"\ndescription: "%s"\nweight: %s\n---\n\n' \
      "${title//\"/\\\"}" "${desc//\"/\\\"}" "$weight"
    tail -n +2 "$src" | rewrite_links
  } > "$dest"
  echo "sync: $dest"
}

i=10
for p in "${PACKAGES[@]}"; do
  page_from_readme "$REPO/packages/$p/README.md" "$CONTENT/packages/$p.md" "$i"
  i=$((i + 5))
done
i=10
for e in "${EXAMPLES[@]}"; do
  page_from_readme "$REPO/examples/$e/README.md" "$CONTENT/examples/$e.md" "$i"
  i=$((i + 5))
done
page_from_readme "$REPO/CONTRIBUTING.md" "$CONTENT/contributing.md" 10

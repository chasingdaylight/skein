#!/usr/bin/env bash
# Builds the documentation site with Zine (#322): docs/ as it is, skein's
# own requirements as `skein render` writes them, and the example projects'
# sites, put together in .site/md; then site/ (a Zig package of its own,
# since skein itself fetches nothing) turns them into pages. An edition of
# each earlier release (#260): the docs and requirements of its tag, under
# vX.Y.Z/, with the skein of that tag; the latest is at the root.
#
#   tools/site.sh [OUT]     OUT defaults to .site/public
#
# Needs skein built (zig build); SKEIN names another one, and ZIG the Zig
# that builds the site and each release's skein (default: zig). Run from the
# repository root. The workflow that builds the site (site.yml, for this
# repository's Pages and the mirror's) calls this. EDITIONS=0 leaves the
# releases out.
# cspell:ignore Dcontent
set -euo pipefail

out=${1:-.site/public}
skein=${SKEIN:-zig-out/bin/skein}
zig=${ZIG:-zig}
md=.site/md

# DOCS_DIR SKEIN ROOT DEST: docs/ of ROOT, and its requirements rendered by SKEIN
pages() {
  mkdir -p "$4"
  cp -R "$1/." "$4/"
  # the sources skein reads are under docs/, so its output lands there too
  local rendered
  rendered=$(mktemp -d)
  "$2" render --root "$3" --out "$rendered" > /dev/null
  cp -R "$rendered/docs/." "$4/"
  rm -rf "$rendered"
  # each example project as a site of its own, as `skein render` makes it
  local example
  for example in "$3"/examples/*/; do
    [ -d "$example.skein" ] || continue
    "$2" render --root "$example" --format html --out "$4/examples/$(basename "$example")" > /dev/null ||
      echo "site.sh: $example: not rendered" >&2
  done
}

version_of() { sed -nE 's/^\s*\.version = "([^"]+)",/\1/p' "$1/build.zig.zon"; }

rm -rf "$md" "$out"
mkdir -p "$md"
pages docs "$skein" . "$md"
latest=$(version_of .)
printf '%s\n' "$latest" > "$md/skein-version.txt"
releases="\"$latest\""

editions=0
if [ "${EDITIONS:-1}" != 0 ] && git rev-parse --git-dir > /dev/null 2>&1; then
  # a shallow checkout has no tags: take them
  git fetch -q --depth=1 origin 'refs/tags/v*:refs/tags/v*' 2> /dev/null || true
  for tag in $(git tag -l 'v[0-9]*' --sort=-version:refname); do
    v=${tag#v}
    [ "$v" = "$latest" ] && continue
    # an edition needs the tag's own script: the site began with it
    git cat-file -e "$tag:tools/site.sh" 2> /dev/null || continue
    tree=$(mktemp -d)
    git archive "$tag" | tar -x -C "$tree"
    if ! (cd "$tree" && "$zig" build > /dev/null 2>&1); then
      echo "site.sh: $tag: its skein does not build with $("$zig" version); left out" >&2
      rm -rf "$tree"
      continue
    fi
    tag_skein=$tree/zig-out/bin/skein
    [ -x "$tag_skein" ] || tag_skein=$tag_skein.exe
    pages "$tree/docs" "$tag_skein" "$tree" "$md/$tag"
    releases="$releases, \"$v\""
    rm -rf "$tree"
    editions=$((editions + 1))
  done
fi
printf '{"releases": [%s]}\n' "$releases" > "$md/skein-editions.json"

# the pages, by Zine; mermaid.js for the diagrams, the copy skein vendors,
# and the logo
cp vendor/mermaid/mermaid.min.js docs/assets/logo.svg site/assets/
build=$(cd .site && pwd)/build
(cd site && "$zig" build -Dcontent="../$md" -p "$build")
mkdir -p "$out"
cp -R "$build/public/." "$out/"
# beside the pages, where Zine wrote nothing: their Markdown (llms.txt and
# each page's alternate link point at it), the images, the example
# projects' sites; and at the root what browsers and agents ask for there
target=$(cd "$out" && pwd)
(cd "$md" && find . -type f ! -name 'skein-*' | while IFS= read -r f; do
  [ -e "$target/$f" ] && continue
  mkdir -p "$target/$(dirname "$f")"
  cp "$f" "$target/$f"
done)
cp site/llms.txt site/assets/favicon.ico "$out/"
echo "site in $out: $(find "$md" -name '*.md' | wc -l) pages, version $latest and $editions earlier edition(s)"

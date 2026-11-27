#!/usr/bin/env bash
# Puts together the source of the documentation site, for Jekyll to build:
# docs/ as it is, skein's own requirements as `skein render` writes them,
# and the layout and settings of site/. Then an edition of each earlier
# release (#260): the docs and requirements of its tag, under vX.Y.Z/, with
# the skein of that tag, and _data/editions.yml, which the layout lists, the
# latest first.
#
#   tools/site.sh [OUT]     OUT defaults to .site/src
#
# Needs skein built (zig build); SKEIN names another one, and ZIG the Zig
# that builds each release's skein (default: zig). Run from the repository
# root. The workflows that publish the site call this, here and in the
# mirror, so both sites are built the same way. EDITIONS=0 leaves the
# releases out.
set -euo pipefail

out=${1:-.site/src}
skein=${SKEIN:-zig-out/bin/skein}
zig=${ZIG:-zig}

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

rm -rf "$out"
mkdir -p "$out"
pages docs "$skein" . "$out"
cp -R site/. "$out/"
# mermaid.js for the diagrams of the docs pages, the copy skein vendors
mkdir -p "$out/assets"
cp vendor/mermaid/mermaid.min.js "$out/assets/"
latest=$(version_of .)
mkdir -p "$out/_data"
printf -- '- version: "%s"\n  dir: ""\n' "$latest" > "$out/_data/editions.yml"

editions=0
if [ "${EDITIONS:-1}" != 0 ] && git rev-parse --git-dir > /dev/null 2>&1; then
  # a shallow checkout (the mirror's) has no tags: take them
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
    pages "$tree/docs" "$tag_skein" "$tree" "$out/$tag"
    printf -- '- version: "%s"\n  dir: "%s"\n' "$v" "$tag" >> "$out/_data/editions.yml"
    rm -rf "$tree"
    editions=$((editions + 1))
  done
fi
echo "site source in $out: $(find "$out" -name '*.md' | wc -l) pages, version $latest and $editions earlier edition(s)"

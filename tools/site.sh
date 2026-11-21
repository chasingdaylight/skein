#!/usr/bin/env bash
# Puts together the source of the documentation site, for Jekyll to build:
# docs/ as it is, skein's own requirements as `skein render` writes them,
# and the layout and settings of site/.
#
#   tools/site.sh [OUT]     OUT defaults to .site/src
#
# Needs skein built (zig build); SKEIN names another one. Run from the
# repository root. The workflows that publish the site call this, here and
# in the mirror, so both sites are built the same way.
set -euo pipefail

out=${1:-.site/src}
skein=${SKEIN:-zig-out/bin/skein}

rm -rf "$out"
mkdir -p "$out"
cp -R docs/. "$out/"

# the sources skein reads are under docs/, so its output lands there too
rendered=$(mktemp -d)
"$skein" render --out "$rendered"
cp -R "$rendered/docs/." "$out/"
rm -rf "$rendered"

cp -R site/. "$out/"
echo "site source in $out: $(find "$out" -name '*.md' | wc -l) pages"

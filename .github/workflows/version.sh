#!/usr/bin/env bash
# version.sh: skein's version and every place that states it, run from the
# repository root by ci.yml and tools/agent/land.sh. A new place that states
# the version is added here.
#   version.sh           prints the version; fails, listing the places, when
#                        one is missing or differs from build.zig.zon
#   version.sh set NEXT  sets every place to NEXT and opens its changelog
#                        section, as CI does when it begins the next version
set -euo pipefail

zon=build.zig.zon
pkg=editors/vscode/package.json
lock=editors/vscode/package-lock.json
log=editors/vscode/CHANGELOG.md
# the action's examples of its use, at the version released
action=action.yml
ci_doc=docs/commands.md
count=7

# places: one "FILE: VERSION" line for each place that states the version
places() {
  sed -nE 's/^    \.version = "([^"]+)",$/\1/p' "$zon" | sed "s|^|$zon: |"
  sed -nE 's/^  "version": "([^"]+)",$/\1/p' "$pkg" | sed "s|^|$pkg: |"
  # the package's own two entries: the top level and packages[""]
  sed -nE '/^ {2,6}"name": "skein",$/{n;s/^ +"version": "([^"]+)",$/\1/p}' "$lock" | sed "s|^|$lock: |"
  # the first section: the version being made, or on main the one released
  sed -nE '/^## /{s/^## ([^ ]+)( \(unreleased\))?$/\1/p;q}' "$log" | sed "s|^|$log: |"
  sed -nE 's|^#   - uses: chasingdaylight/skein@v([^ ]+)$|\1|p' "$action" | sed "s|^|$action: |"
  sed -nE 's|^      - uses: chasingdaylight/skein@v([^ ]+)$|\1|p' "$ci_doc" | sed "s|^|$ci_doc: |"
}

check() {
  local version list bad
  version=$(sed -nE 's/^    \.version = "([^"]+)",$/\1/p' "$zon")
  list=$(places)
  bad=$(grep -v ": $version\$" <<< "$list" || true)
  if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$(grep -c . <<< "$list")" -ne "$count" ] || [ -n "$bad" ]; then
    echo "version.sh: the $count places that state the version must all be $zon's MAJOR.MINOR.PATCH ('$version'); found:" >&2
    echo "$list" >&2
    exit 1
  fi
  echo "$version"
}

set_version() {
  local next=$1
  [[ $next =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version.sh: '$next' is not MAJOR.MINOR.PATCH" >&2; exit 1; }
  sed -i -E "s/^(    \.version = \")[^\"]+(\",)$/\1$next\2/" "$zon"
  sed -i -E "s/^(  \"version\": \")[^\"]+(\",)$/\1$next\2/" "$pkg"
  sed -i -E "/^ {2,6}\"name\": \"skein\",$/{n;s/^( +\"version\": \")[^\"]+(\",)$/\1$next\2/}" "$lock"
  sed -i -E "s|^(#   - uses: chasingdaylight/skein@v)[^ ]+$|\1$next|" "$action"
  sed -i -E "s|^(      - uses: chasingdaylight/skein@v)[^ ]+$|\1$next|" "$ci_doc"
  # a section for NEXT above the others, which are then released
  if [ "$(grep -m1 '^## ' "$log")" != "## $next (unreleased)" ]; then
    { printf '# Changelog\n\n## %s (unreleased)\n\n' "$next"; tail -n +3 "$log" | sed -E 's/^(## .*) \(unreleased\)$/\1/'; } > "$log.new"
    mv "$log.new" "$log"
  fi
  check > /dev/null
}

case "${1:-}" in
  "") check ;;
  set) set_version "${2:?version.sh set NEXT}" ;;
  *) echo "version.sh: [set NEXT]" >&2; exit 1 ;;
esac

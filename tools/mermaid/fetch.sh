#!/usr/bin/env bash
# fetch.sh [VERSION]: puts mermaid's browser build (dist/mermaid.min.js) and its
# license into vendor/mermaid/, from the npm registry, checked against the
# integrity hash the registry publishes for the package; the latest release
# when no VERSION is given. Prints the version. Used by hand and by the
# mermaid-updates workflow.
# cspell:ignore dgst
set -euo pipefail
cd "$(dirname "$0")/../.."
want=${1:-latest}
meta=$(curl -sSf "https://registry.npmjs.org/mermaid/$want")
# the first of each key: the package's own version, and its tarball's (no jq needed)
field() { printf '%s' "$meta" | grep -o "\"$1\": *\"[^\"]*\"" | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }
version=$(field version)
tarball=$(field tarball)
integrity=$(field integrity)
[ -n "$version" ] && [ -n "$tarball" ] || { echo "fetch.sh: no release of mermaid '$want'" >&2; exit 1; }
case "$integrity" in sha512-*) ;; *) echo "fetch.sh: no sha512 integrity for mermaid $version" >&2; exit 1 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sSfL -o "$work/mermaid.tgz" "$tarball"
got="sha512-$(openssl dgst -sha512 -binary "$work/mermaid.tgz" | openssl base64 -A)"
[ "$got" = "$integrity" ] || { echo "fetch.sh: mermaid $version does not match its integrity hash" >&2; exit 1; }
tar -xzf "$work/mermaid.tgz" -C "$work" package/dist/mermaid.min.js package/LICENSE package/package.json
mkdir -p vendor/mermaid
cp "$work/package/dist/mermaid.min.js" vendor/mermaid/mermaid.min.js
cp "$work/package/LICENSE" vendor/mermaid/LICENSE
printf '%s\n' "$version" > vendor/mermaid/VERSION
echo "$version"

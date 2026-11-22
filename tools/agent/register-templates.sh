#!/usr/bin/env bash
# register-templates.sh: writes the list of templates/__root__.zig from the
# files of templates/, langspec first and the others by name, each
# template's files in name order. Run after adding or removing a file of a
# template; a test holds the list to the directory.
set -euo pipefail
cd "$(dirname "$0")/../../templates"
out=$(mktemp)
{
  sed -n '1,/^pub const files = \[_\]File{$/p' __root__.zig
  for t in langspec $(ls -d */ | tr -d / | grep -v '^langspec$'); do
    find "$t" -type f | sort -t/ -k2 | while read -r f; do
      echo "    .{ .template = \"$t\", .path = \"${f#"$t"/}\", .data = @embedFile(\"$f\") },"
    done
  done
  echo "};"
} > "$out"
mv "$out" __root__.zig
echo "templates/__root__.zig: $(grep -c '\.template = ' __root__.zig) files"

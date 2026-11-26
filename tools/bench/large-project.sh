#!/usr/bin/env bash
# large-project.sh DIR [DOCS] [TESTS]: writes a large project into DIR for
# timing skein (#128): DOCS documents of 200 requirements each (default 100,
# 20,000 requirements), TESTS test files citing four requirements each
# (default 5,000), and results.toml with a result for each test file. Then,
# from DIR: time skein coverage --results results.toml
set -euo pipefail
dir=${1:?large-project.sh DIR [DOCS] [TESTS]}
docs=${2:-100}
tests=${3:-5000}
mkdir -p "$dir/.skein/types" "$dir/spec" "$dir/tests"
cd "$dir"
printf '[[sources]]\npath = "spec"\n\n[[citations]]\nname = "test"\npath = "tests"\nfiles = [".zig"]\nmarker = "// req:"\nto = ["req"]\nexpected = true\n' > .skein/config.toml
: > .skein/types/req.toml
for d in $(seq 0 $((docs - 1))); do
  for i in $(seq 0 199); do printf '%%req[r.d%d.i%d] Requirement %d shall hold.\n\n' "$d" "$i" $((d * 200 + i)); done > "spec/d$d.md"
done
total=$((docs * 200))
for t in $(seq 0 $((tests - 1))); do
  ids=""
  for k in 0 1 2 3; do
    n=$(((t * 4 + k) % total))
    ids="$ids${ids:+, }r.d$((n / 200)).i$((n % 200))"
  done
  printf '// req: %s\ntest "t%d" {}\n' "$ids" "$t" > "tests/t$t.zig"
  printf '[[result]]\nfile = "tests/t%d.zig"\nresult = "pass"\n\n' "$t"
done > results.toml
echo "large-project.sh: $total requirements, $tests test files and results in $dir"

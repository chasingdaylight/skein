#!/usr/bin/env bash
# fetch.sh DIR: saves the pages of NPR 7150.2D that tools/npr7150 reads
# (chapters 2 to 5 and appendix C) from NODIS into DIR, then:
#   zig build npr7150 -- DIR templates/npr7150.2d/project/standards/npr7150.2d YYYY-MM-DD
set -euo pipefail
dir=${1:?usage: fetch.sh DIR}
mkdir -p "$dir"
for page in Chapter2 Chapter3 Chapter4 Chapter5 AppendixC; do
  curl -sSf -o "$dir/$page.html" "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=$page"
  sleep 2
done
echo "fetched into $dir"

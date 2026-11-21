# shellcheck shell=bash
# Which changed files can change the shipped binary. Sourced (in bash, from
# the repository root) by ci.yml's "Changes" job, which decides whether a
# pull request needs the checks. From zfls's changes.sh; the release
# decisions it also makes there come here with the first release.

# patterns LIST...: the globs of the lists (one bash `case` glob per line;
# lines starting with # and blank lines are ignored)
patterns() { cat "$@" | grep -v '^\s*#' | grep -v '^\s*$'; }

# matches FILE GLOB...: whether FILE matches one of the globs
matches() {
    local f=$1 pat
    shift
    for pat in "$@"; do
        # shellcheck disable=SC2254
        case "$f" in $pat) return 0 ;; esac
    done
    return 1
}

# The files whose changes alone skip CI, and the files that cannot change
# the shipped binary (used where this is sourced)
# shellcheck disable=SC2034
mapfile -t no_ci < <(patterns .github/workflows/no-ci.txt)
# shellcheck disable=SC2034
mapfile -t exempt < <(patterns .github/workflows/no-ci.txt .github/workflows/ci-only.txt)

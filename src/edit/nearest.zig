//! The word a misspelled one most likely meant: the closest by edit
//! distance (insertions, deletions, substitutions, and swaps of two
//! neighbors), within a bound.

const std = @import("std");

/// The longest word compared; longer ones match nothing
const max_len = 64;

/// The candidate closest to `word`, within `max` edits and closer than any
/// other; null when none is, or two are as close
pub fn nearest(word: []const u8, candidates: []const []const u8, max: usize) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_d: usize = max + 1;
    var tied = false;
    for (candidates) |c| {
        if (std.mem.eql(u8, c, word)) continue;
        const d = distance(word, c, max);
        if (d < best_d) {
            best = c;
            best_d = d;
            tied = false;
        } else if (d == best_d and best != null and !std.mem.eql(u8, best.?, c)) tied = true;
    }
    return if (tied) null else best;
}

/// The edit distance of `a` and `b`, or `max + 1` when it is more
pub fn distance(a: []const u8, b: []const u8, max: usize) usize {
    if (a.len > max_len or b.len > max_len) return max + 1;
    if ((if (a.len > b.len) a.len - b.len else b.len - a.len) > max) return max + 1;
    // three rows: the one before last, the last, and this one
    var rows: [3][max_len + 1]usize = undefined;
    for (0..b.len + 1) |j| rows[1][j] = j;
    for (1..a.len + 1) |i| {
        const cur = &rows[(i + 1) % 3];
        const prev = &rows[i % 3];
        const prev2 = &rows[(i + 2) % 3];
        cur[0] = i;
        for (1..b.len + 1) |j| {
            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
            var d = @min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
            if (i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]) d = @min(d, prev2[j - 2] + 1);
            cur[j] = d;
        }
    }
    return @min(rows[(a.len + 1) % 3][b.len], max + 1);
}

// cspell:ignore verifes tokne syntx
const testing = std.testing;

test distance {
    try testing.expectEqual(0, distance("verifies", "verifies", 2));
    try testing.expectEqual(1, distance("verifes", "verifies", 2));
    try testing.expectEqual(1, distance("lex.tokne", "lex.token", 2));
    try testing.expectEqual(2, distance("syntx", "syntax2", 2));
    try testing.expectEqual(3, distance("abc", "xyz", 2));
    try testing.expectEqual(3, distance("a", "abcdef", 2));
}

test nearest {
    try testing.expectEqualStrings("verifies", nearest("verifes", &.{ "refines", "verifies", "derives" }, 2).?);
    try testing.expectEqual(null, nearest("zzz", &.{ "refines", "verifies" }, 2));
    // two as close: no guess
    try testing.expectEqual(null, nearest("lex.b", &.{ "lex.a", "lex.c" }, 2));
}

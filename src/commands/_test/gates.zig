//! The gates of a milestone, on a git repository made for the test: the
//! share of undecided items, and of items changed since the last baseline.

// req: control.gates
const std = @import("std");
const testing = std.testing;

const Repo = @import("Repo.zig");
const check_command = @import("../check.zig");
const coverage_command = @import("../coverage.zig");

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

test "undecided items and volatility against the gate of the milestone" {
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    try repo.write(".skein/config.toml",
        \\[[sources]]
        \\path = "spec"
        \\
        \\[maturity]
        \\milestone = "pdr"
        \\
        \\[maturity.gates.pdr]
        \\tbd = 10
        \\volatility = 20
        \\
    );
    try repo.write(".skein/types/rule.toml", "statuses = [\"draft\", \"tbd\", \"tbr\"]\n");
    try repo.write(".skein/types/note.toml", "");
    try repo.write("spec/lex.md",
        \\%rule[lex.a] A.
        \\
        \\%rule[lex.b] B.
        \\
        \\%rule[lex.c] C.
        \\
        \\%rule[lex.d] D.
        \\
        \\%rule[lex.e] E.
        \\
        \\%note[n.one] Not counted.
        \\
    );
    try repo.commit("rules");
    try testing.expect((try repo.baseline("b1", null)).ok);
    // no change since: nothing to say
    try expectContains((try check_command.run(testing.io, a, .{ .root = repo.root })).text, "no problems");

    // one of five undecided (20% > 10%), and two of five changed (40% >= 20%)
    try repo.write("spec/lex.md",
        \\%rule[lex.a tbd] A, undecided.
        \\
        \\%rule[lex.b] B, changed.
        \\
        \\%rule[lex.c] C.
        \\
        \\%rule[lex.d] D.
        \\
        \\%rule[lex.e] E.
        \\
        \\%note[n.one] Not counted, changed.
        \\
    );
    const out = (try check_command.run(testing.io, a, .{ .root = repo.root })).text;
    try expectContains(out, "warning: at pdr, 1 of the 5 items (20%) are undecided (tbd, tbr); the gate is at most 10%");
    try expectContains(out, "warning: at pdr, 2 of the 5 items of baseline b1 (40%) were added, changed or removed since; the gate is under 20%");
    const cov = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = repo.root } })).text;
    try expectContains(cov, "gate at pdr:\n  undecided (tbd, tbr): 1 of 5 (20%), at most 10%\n  changed since baseline b1: 2 of 5 (40%), under 20%\n");

    // another milestone without a gate: nothing to say of it
    try repo.write(".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[maturity]\nmilestone = \"cdr\"\n\n[maturity.gates.pdr]\ntbd = 10\n");
    try testing.expect(std.mem.find(u8, (try check_command.run(testing.io, a, .{ .root = repo.root })).text, "gate") == null);
    try repo.write(".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[maturity]\nmilestone = \"pdr\"\n\n[maturity.gates.pdr]\ntbd = 120\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = repo.root })).text, "a share in percent, 0 to 100");
}

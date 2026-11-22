//! Test results on a project made for the test: tests that cite rules, a
//! procedure run by a person, results kept in the project and given on
//! the command line.

// req: results.import, results.mapping, results.verdicts, results.kept, results.unmatched
const std = @import("std");
const testing = std.testing;

const check_command = @import("../../commands/check.zig");
const coverage_command = @import("../../commands/coverage.zig");
const result_command = @import("../../commands/result.zig");
const render_command = @import("../../commands/render.zig");
const trace_command = @import("../../commands/trace.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.find(u8, haystack, needle) == null) {
        std.debug.print("expected to find:\n{s}\nin:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Fixture) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml",
            \\[[sources]]
            \\path = "spec"
            \\
            \\[[citations]]
            \\name = "test"
            \\path = "tests"
            \\files = [".zig"]
            \\marker = "// spec:"
            \\to = ["rule"]
            \\expected = true
            \\
            \\[results]
            \\paths = ["verification/results"]
            \\
        );
        try write(dir, ".skein/types/rule.toml", "");
        try write(dir, ".skein/types/procedure.toml", "");
        try write(dir, ".skein/links/verifies.toml", "from = [\"procedure\"]\nto = [\"rule\"]\n");
        try write(dir, "spec/lex.md",
            \\%rule[lex.a] First.
            \\
            \\%rule[lex.b] Second.
            \\
            \\%rule[lex.c] Third, inspected by hand.
            \\
            \\%rule[lex.d] Fourth, with no test.
            \\
            \\%procedure[tp.inspect verifies=lex.c] Look at the listing.
            \\
        );
        try write(dir, "tests/one.zig", "// spec: lex.a\ntest \"a\" {}\n");
        try write(dir, "tests/two.zig", "// spec: lex.a, lex.b\ntest \"b\" {}\n");
        try write(dir, "verification/results/run.toml",
            \\[[result]]
            \\test = "a"
            \\file = "tests/one.zig"
            \\result = "pass"
            \\implementation = "cesium0"
            \\version = "0.3.1"
            \\
            \\[[result]]
            \\test = "b"
            \\file = "tests/two.zig"
            \\result = "fail"
            \\implementation = "cesium0"
            \\
            \\[[result]]
            \\item = "tp.inspect"
            \\result = "pass"
            \\implementation = "cesium0"
            \\note = "Checked by hand."
            \\
            \\[[result]]
            \\test = "lost"
            \\file = "tests/gone.zig"
            \\result = "pass"
            \\implementation = "cesium0"
            \\
        );
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Fixture) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }
};

test "results kept in the project: verdicts per item, and what belongs to none" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    const out = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root } })).text;
    // lex.a: a pass and a fail (two.zig cites it too); lex.b fails; lex.c by the procedure
    try expectContains(out, "results (cesium0 0.3.1): 2 of 5 passed, 2 failed, 1 untested\n  failed:\n    lex.a\n    lex.b\n  untested:\n    lex.d\n");
    try expectContains(out, "1 result that belongs to no item:\n  lost  (verification/results/run.toml, result 4)\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = f.root })).text, "verification/results/run.toml: warning: result 4 (lost) belongs to no item");

    const traced = (try trace_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .id = "lex.c" })).text;
    try expectContains(traced, "\nResults:\n  cesium0 0.3.1: passed\n    pass  tp.inspect  (verification/results/run.toml, result 3)\n");
}

// req: results.rendered
test "a generated coverage page shows the results" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try write(f.tmp.dir, "spec/status.md", "# Status\n\n```skein\ncoverage\n```\n");
    const out_dir = try std.Io.Dir.path.join(a, &.{ f.root, "out" });
    const rendered = try render_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .out = out_dir });
    try testing.expectEqual(.ok, rendered.status);
    const page = try f.tmp.dir.readFileAlloc(testing.io, "out/spec/status.md", a, .limited(1 << 16));
    try expectContains(page, "| Results | Passed | Failed | Untested |\n| --- | ---: | ---: | ---: |\n| cesium0 0.3.1 | 2 of 5 | 2 | 1 |\n");
    try expectContains(page, "Failed in cesium0 0.3.1: [`lex.a`](lex.md#lex.a), [`lex.b`](lex.md#lex.b).");
}

// req: verification.records, verification.coverage
test "items are verified as their method requires: by a test, or by a record" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try write(f.tmp.dir, ".skein/types/rule.toml", "verification = [\"test\", \"inspection\", \"analysis\"]\n");
    try write(f.tmp.dir, "spec/lex.md",
        \\%rule[lex.a verification=test] Tested, and one of its tests fails.
        \\
        \\%rule[lex.b verification=test] Tested.
        \\
        \\%rule[lex.c verification=inspection] Inspected by hand.
        \\
        \\%rule[lex.d verification=analysis] Not analyzed yet.
        \\
        \\%procedure[tp.inspect verifies=lex.c] Look at the listing.
        \\
    );
    try write(f.tmp.dir, "tests/two.zig", "// spec: lex.b\ntest \"b\" {}\n");
    try write(f.tmp.dir, "reports/listing.txt", "Looked at it.\n");
    const recorded = try result_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .id = "tp.inspect", .outcome = .pass, .by = "A. Tester", .on = "2026-11-22", .evidence = &.{ "reports/listing.txt", "reports/missing.txt" } });
    try testing.expectEqual(.ok, recorded.status);
    try expectContains(try f.tmp.dir.readFileAlloc(testing.io, "verification/results/recorded.toml", a, .limited(1 << 16)), "evidence = [\"reports/listing.txt\", \"reports/missing.txt\"]\n");

    const out = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root } })).text;
    // tests/one.zig cites lex.a and passes; tests/two.zig now cites lex.b alone, and fails
    try expectContains(out, "verified as their method requires:\n  test: 1 of 2 (50%)\n    not verified:\n      lex.b\n  inspection: 1 of 1 (100%)\n  analysis: 0 of 1 (0%)\n    not verified:\n      lex.d\n");
    try expectContains((try check_command.run(testing.io, a, .{ .root = f.root })).text, "verification/results/recorded.toml: warning: result 1 (tp.inspect): its evidence 'reports/missing.txt' is not in the project");
}

// req: results.recorded, results.stale
test "a result a person records, which is stale once what it verified changes" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try write(f.tmp.dir, "spec/more.md", "%procedure[tp.two verifies=lex.d] Read it out loud.\n");
    const recorded = try result_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .id = "tp.two", .outcome = .pass, .by = "A. Tester", .on = "2026-11-22", .note = "Fine.", .implementation = "cesium0" });
    try testing.expectEqualStrings("skein: recorded that tp.two passed, by A. Tester, in verification/results/recorded.toml\n", recorded.text);
    const text = try f.tmp.dir.readFileAlloc(testing.io, "verification/results/recorded.toml", a, .limited(1 << 16));
    try expectContains(text, "[[result]]\nitem = \"tp.two\"\nresult = \"pass\"\nby = \"A. Tester\"\ndate = 2026-11-22\n");
    // the commit, when the project is in a git repository, comes between
    try expectContains(text, "implementation = \"cesium0\"\nnote = \"Fine.\"\nfingerprints = [\"tp.two=");
    try expectContains(text, "\", \"lex.d=");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root } })).text, "results (cesium0 0.3.1): 4 of 6 passed, 2 failed, 0 untested\n");

    // lex.d changes: the result no longer says anything of it
    try write(f.tmp.dir, "spec/lex.md", try std.mem.replaceOwned(u8, a, try f.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", a, .limited(1 << 16)), "Fourth, with no test.", "Fourth, changed."));
    try expectContains((try check_command.run(testing.io, a, .{ .root = f.root })).text, "verification/results/recorded.toml: warning: result 1 (tp.two) is stale: 'lex.d' has changed since it was recorded");
    try expectContains((try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root } })).text, "untested:\n    lex.d\n");
}

test "results given on the command line, of another implementation, in JSON and YAML" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const a = f.arena.allocator();
    try write(f.tmp.dir, "run2.json", "[{\"file\": \"tests/one.zig\", \"result\": \"pass\", \"implementation\": \"cesium1\"}]");
    try write(f.tmp.dir, "run3.yaml", "result:\n  - items:\n      - lex.b\n      - lex.d\n    result: pass\n    implementation: cesium1\n");
    const files = [_][]const u8{ try std.Io.Dir.path.join(a, &.{ f.root, "run2.json" }), try std.Io.Dir.path.join(a, &.{ f.root, "run3.yaml" }) };
    const out = (try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .results = &files })).text;
    try expectContains(out, "results (cesium0 0.3.1): 2 of 5 passed");
    try expectContains(out, "results (cesium1): 3 of 5 passed, 0 failed, 2 untested\n  untested:\n    lex.c\n    tp.inspect\n");

    try write(f.tmp.dir, "bad.toml", "[[result]]\ntest = \"x\"\nresult = \"maybe\"\n");
    const bad = [_][]const u8{try std.Io.Dir.path.join(a, &.{ f.root, "bad.toml" })};
    const refused = try coverage_command.run(testing.io, a, .{ .common = .{ .root = f.root }, .results = &bad });
    try testing.expectEqual(.problems, refused.status);
    try expectContains(refused.text, "result 1: 'maybe' is not pass, fail or skip");
}

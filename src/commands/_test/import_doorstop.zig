//! `skein import doorstop`, on Doorstop documents written for the test.

const std = @import("std");
const testing = std.testing;

const check = @import("../check.zig");
const import_doorstop = @import("../import_doorstop.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

/// Two documents: system requirements, and software requirements that
/// link to them
fn doorstop(dir: std.Io.Dir) !void {
    try write(dir, "docs/sys/.doorstop.yml",
        \\settings:
        \\  digits: 3
        \\  prefix: SYS
        \\  sep: '-'
        \\attributes:
        \\  defaults:
        \\    doc:
        \\      title: "System Requirements"
        \\  reviewed:
        \\  - category
    );
    try write(dir, "docs/sys/SYS-001.md",
        \\---
        \\active: true
        \\category: capability
        \\derived: false
        \\level: 1.1
        \\links: []
        \\normative: true
        \\ref: ''
        \\reviewed: ItJnz4iOh-o61yl1qcExgZFnsE9aDaUKq3ZxblNJ4Zw=
        \\---
        \\
        \\# Solving
        \\
        \\The system **shall** solve the problem.
    );
    try write(dir, "docs/sys/SYS-002.md", "---\nactive: true\ncategory: constraint\nlinks: []\n---\n\nThe system **shall** run offline.\n");
    try write(dir, "docs/sys/notes.md", "Not an item: its name does not start with the prefix.\n");
    try write(dir, "docs/srs/.doorstop.yml", "settings:\n  digits: 3\n  prefix: SRS\n  sep: '-'\n  parent: SYS\n");
    try write(dir, "docs/srs/SRS-001.md",
        \\---
        \\active: true
        \\links:
        \\- SYS-001: ItJnz4iOh-o61yl1qcExgZFnsE9aDaUKq3ZxblNJ4Zw=
        \\- SYS-002
        \\status: done
        \\---
        \\
        \\The software **shall** read the problem.
    );
    try write(dir, "docs/srs/SRS-002.yml", "active: false\nheader: Old\nlinks: []\ntext: |\n  No longer wanted.\n");
}

fn run(a: std.mem.Allocator, dir: std.Io.Dir, paths: []const []const u8) ![]const u8 {
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    return (try import_doorstop.run(testing.io, a, .{ .common = .{ .root = root }, .paths = paths })).text;
}

fn read(a: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
    return dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
}

test "Doorstop documents become a skein project that checks clean but for the links to review" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try doorstop(tmp.dir);

    try testing.expectEqualStrings(
        "skein: imported 4 items of 2 Doorstop documents; 1 link recorded as reviewed\n" ++
            "       Look over the changes ('git diff'), then run 'skein check'.\n",
        try run(a, tmp.dir, &.{ "docs/sys", "docs/srs/" }),
    );

    try testing.expectEqualStrings(
        \\[[sources]]
        \\path = "docs/sys"
        \\kind = "items"
        \\type = "sys"
        \\
        \\[[sources]]
        \\path = "docs/srs"
        \\kind = "items"
        \\type = "srs"
        \\
    , try read(a, tmp.dir, ".skein/config.toml"));
    try testing.expectEqualStrings(
        \\description = "System Requirements"
        \\id = "numbered"
        \\prefix = "SYS"
        \\digits = 3
        \\categories = ["capability", "constraint"]
        \\
        \\[attributes.level]
        \\
    , try read(a, tmp.dir, ".skein/types/sys.toml"));
    try testing.expectEqualStrings(
        \\+++
        \\id = "SYS-001"
        \\category = "capability"
        \\level = "1.1"
        \\+++
        \\
        \\# Solving
        \\
        \\The system **shall** solve the problem.
        \\
    , try read(a, tmp.dir, "docs/sys/SYS-001.md"));
    try testing.expectEqualStrings(
        \\+++
        \\id = "SRS-001"
        \\parent = ["SYS-001", "SYS-002"]
        \\doorstop-status = "done"
        \\+++
        \\
        \\The software **shall** read the problem.
        \\
    , try read(a, tmp.dir, "docs/srs/SRS-001.md"));
    try testing.expectEqualStrings(
        \\+++
        \\id = "SRS-002"
        \\status = "removed"
        \\+++
        \\
        \\# Old
        \\
        \\No longer wanted.
        \\
    , try read(a, tmp.dir, "docs/srs/SRS-002.md"));
    // Doorstop's own files are gone; what was not an item is left
    try testing.expectError(error.FileNotFound, read(a, tmp.dir, "docs/srs/SRS-002.yml"));
    try testing.expectError(error.FileNotFound, read(a, tmp.dir, "docs/sys/.doorstop.yml"));
    try testing.expectEqualStrings("Not an item: its name does not start with the prefix.\n", try read(a, tmp.dir, "docs/sys/notes.md"));

    // the link Doorstop had a review of is reviewed; the other is to be
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);
    try testing.expectEqualStrings(
        \\docs/srs/SRS-001.md:1:1: error: SRS-001: parent: the link to 'SYS-002' was never reviewed ('skein review SRS-001')
        \\skein: 1 problem
        \\
    , (try check.run(testing.io, a, .{ .root = root })).text);
}

test "importing into a project that exists adds to it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try doorstop(tmp.dir);
    try write(tmp.dir, ".skein/config.toml", "[project]\nname = \"example\"\n");
    try write(tmp.dir, ".skein/types/srs.toml", "");

    try testing.expectEqualStrings("skein: there is an item type 'srs' already (.skein/types/srs.toml)\n", try run(a, tmp.dir, &.{"docs/srs"}));
    // nothing of that document was changed
    try testing.expect(std.mem.startsWith(u8, try read(a, tmp.dir, "docs/srs/SRS-001.md"), "---\n"));

    _ = try run(a, tmp.dir, &.{"docs/sys"});
    try testing.expectEqualStrings(
        \\[project]
        \\name = "example"
        \\
        \\[[sources]]
        \\path = "docs/sys"
        \\kind = "items"
        \\type = "sys"
        \\
    , try read(a, tmp.dir, ".skein/config.toml"));
}

test "what is not a Doorstop document" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "docs/plain/readme.md", "Text.\n");
    try write(tmp.dir, "docs/bad/.doorstop.yml", "settings:\n  prefix: BAD\n");
    try write(tmp.dir, "docs/bad/BAD-001.md", "No front matter.\n");
    try testing.expectEqualStrings("skein: 'docs/plain' is no Doorstop document: it has no .doorstop.yml\n", try run(a, tmp.dir, &.{"docs/plain"}));
    try testing.expectEqualStrings("skein: cannot open the directory 'docs/none'\n", try run(a, tmp.dir, &.{"docs/none"}));
    try testing.expectEqualStrings("skein: docs/bad/BAD-001.md:0: this is not what Doorstop writes\n", try run(a, tmp.dir, &.{"docs/bad"}));
}

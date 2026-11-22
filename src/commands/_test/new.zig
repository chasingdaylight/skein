//! `skein new`, on a project on disk.

// req: new.numbered, new.named, new.file, new.marker, new.refusals
const std = @import("std");
const testing = std.testing;

const new_command = @import("../new.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

const Run = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    root: []const u8,

    fn init(self: *Run) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml",
            \\[project]
            \\name = "example"
            \\[[sources]]
            \\path = "spec"
            \\[[sources]]
            \\path = "requirements"
            \\kind = "items"
            \\type = "srs"
            \\[[sources]]
            \\path = "tests/cases"
            \\kind = "items"
        );
        try write(dir, ".skein/types/rule.toml", "");
        try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\nnames = true\n");
        try write(dir, ".skein/types/tst.toml", "id = \"numbered\"\nprefix = \"T\"\nseparator = \"\"\ndigits = 2\n");
        try write(dir, "spec/lex.md", "%rule[lex.token] A token.\n");
        try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\n\nOne.\n");
        try write(dir, "requirements/SRS-007.md", "+++\nid = \"SRS-007\"\nstatus = \"removed\"\n+++\n");
        try write(dir, "requirements/SRS-PURPOSE.md", "+++\nid = \"SRS-PURPOSE\"\n+++\n\nWhy.\n");
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn new(self: *Run, type_name: []const u8, id: ?[]const u8, to: ?[]const u8) ![]const u8 {
        return (try new_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .type_name = type_name, .id = id, .to = to })).text;
    }

    fn file(self: *Run, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

test "a numbered item gets the next free number, in its source of item files" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    // a removed number stays taken, and a name is no number
    try testing.expectEqualStrings("requirements/SRS-008.md\n", try run.new("srs", null, null));
    try testing.expectEqualStrings("+++\nid = \"SRS-008\"\n+++\n\n", try run.file("requirements/SRS-008.md"));
    try testing.expectEqualStrings("requirements/SRS-009.md\n", try run.new("srs", null, null));
    // a source without a type: the type is written in the front matter
    try testing.expectEqualStrings("tests/cases/T01.md\n", try run.new("tst", null, "tests/cases"));
    try testing.expectEqualStrings("+++\nid = \"T01\"\ntype = \"tst\"\n+++\n\n", try run.file("tests/cases/T01.md"));
}

test "an item named by hand, and one that goes in a document" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("requirements/SRS-SCOPE.md\n", try run.new("srs", "SRS-SCOPE", null));
    // a rule has no source of item files: its marker is printed, to paste
    try testing.expectEqualStrings("%rule[lex.comment]\n", try run.new("rule", "lex.comment", null));
}

test "what cannot be made is refused" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: there is no item type 'nope'\n", try run.new("nope", null, null));
    try testing.expectEqualStrings("skein: a 'rule' has IDs joined by dots: name the new one (skein new rule ID)\n", try run.new("rule", null, null));
    try testing.expectEqualStrings("skein: the ID 'lex.token' is taken\n", try run.new("rule", "lex.token", null));
    try testing.expectEqualStrings("skein: the ID 'SRS-007' is taken\n", try run.new("srs", "SRS-007", null));
    try testing.expectEqualStrings("skein: 'SRS-1' is not spelled as the IDs of a 'srs' are\n", try run.new("srs", "SRS-1", null));
    try testing.expectEqualStrings("skein: 'spec' is not a source of item files in .skein/config.toml\n", try run.new("srs", null, "spec"));
    // a file is never written over, even one that is no item
    try write(run.tmp.dir, "requirements/SRS-008.md", "notes\n");
    try testing.expectEqualStrings("skein: there is a file 'requirements/SRS-008.md' already\n", try run.new("srs", null, null));
    try testing.expectEqualStrings("notes\n", try run.file("requirements/SRS-008.md"));
}

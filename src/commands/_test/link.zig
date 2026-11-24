//! `skein link`, on a project on disk.

// req: link.add, link.marker, link.front-matter, link.refusals
const std = @import("std");
const testing = std.testing;

const check_command = @import("../check.zig");
const link_command = @import("../link.zig");

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
        try write(dir, ".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"srs\"\n");
        try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
        try write(dir, ".skein/types/case.toml", "");
        try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n[attributes.priority]\n");
        try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\n");
        try write(dir, ".skein/links/refines.toml", "from = [\"srs\"]\nto = [\"srs\"]\n");
        try write(dir, ".skein/links/see.toml", "");
        try write(dir, "spec/lex.md",
            \\%rule[lex.a syntax] A.
            \\
            \\%rule[lex.b syntax] B.
            \\
            \\%rule[lex.old removed]
            \\
            \\- %case[c.one] Checks.
            \\- %case[c.two verifies=lex.a] Checks too.
            \\
        );
        try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\n\nOne.\n");
        try write(dir, "requirements/SRS-002.md", "+++\r\nid = \"SRS-002\"\r\npriority = \"high\"\r\n+++\r\n\r\nTwo.\r\n");
        try write(dir, "requirements/SRS-003.md", "+++\nid = \"SRS-003\"\nrefines = \"SRS-001\"\n+++\n\nThree.\n");
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
    }

    fn deinit(self: *Run) void {
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn link(self: *Run, from: []const u8, type_name: []const u8, to: []const u8) ![]const u8 {
        return (try link_command.run(testing.io, self.arena.allocator(), .{ .common = .{ .root = self.root }, .from = from, .type_name = type_name, .to = to })).text;
    }

    fn file(self: *Run, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }

    fn checks(self: *Run) ![]const u8 {
        return (try check_command.run(testing.io, self.arena.allocator(), .{ .root = self.root })).text;
    }
};

test "a link is added to a marker, as a new key or to the key's values" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: c.one verifies lex.a\n", try run.link("c.one", "verifies", "lex.a"));
    _ = try run.link("c.two", "verifies", "lex.b");
    _ = try run.link("lex.a", "see", "lex.b");
    const spec = try run.file("spec/lex.md");
    try testing.expect(std.mem.find(u8, spec, "- %case[c.one verifies=lex.a] Checks.\n") != null);
    try testing.expect(std.mem.find(u8, spec, "- %case[c.two verifies=lex.a,lex.b] Checks too.\n") != null);
    try testing.expect(std.mem.find(u8, spec, "%rule[lex.a syntax see=lex.b] A.\n") != null);
    try testing.expect(std.mem.startsWith(u8, try run.checks(), "skein: example: no problems"));
}

test "a link is added to front matter, as a new key or to the key's array or string" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    _ = try run.link("SRS-002", "refines", "SRS-001");
    try testing.expectEqualStrings("+++\r\nid = \"SRS-002\"\r\nrefines = [\"SRS-001\"]\r\npriority = \"high\"\r\n+++\r\n\r\nTwo.\r\n", try run.file("requirements/SRS-002.md"));
    _ = try run.link("SRS-002", "refines", "SRS-003");
    try testing.expect(std.mem.find(u8, try run.file("requirements/SRS-002.md"), "refines = [\"SRS-001\", \"SRS-003\"]\r\n") != null);
    _ = try run.link("SRS-003", "refines", "SRS-002");
    try testing.expectEqualStrings("+++\nid = \"SRS-003\"\nrefines = [\"SRS-001\", \"SRS-002\"]\n+++\n\nThree.\n", try run.file("requirements/SRS-003.md"));
    try testing.expect(std.mem.startsWith(u8, try run.checks(), "skein: example: no problems"));
}

test "a link that check would report is refused, and nothing written" {
    var run: Run = undefined;
    try run.init();
    defer run.deinit();
    try testing.expectEqualStrings("skein: there is no item 'c.nope'\n", try run.link("c.nope", "verifies", "lex.a"));
    try testing.expectEqualStrings("skein: there is no link type 'tests'\n", try run.link("c.one", "tests", "lex.a"));
    try testing.expectEqualStrings("skein: a 'rule' cannot have a 'verifies' link\n", try run.link("lex.a", "verifies", "lex.b"));
    try testing.expectEqualStrings("skein: 'c.two' is a 'case', which a 'verifies' link cannot point to\n", try run.link("c.one", "verifies", "c.two"));
    try testing.expectEqualStrings("skein: there is no item 'lex.nope'\n", try run.link("c.one", "verifies", "lex.nope"));
    try testing.expectEqualStrings("skein: 'lex.old' is removed\n", try run.link("lex.a", "see", "lex.old"));
    try testing.expectEqualStrings("skein: an item cannot link to itself\n", try run.link("lex.a", "see", "lex.a"));
    try testing.expectEqualStrings("skein: c.two has this link already\n", try run.link("c.two", "verifies", "lex.a"));
    try testing.expect(std.mem.find(u8, try run.file("spec/lex.md"), "%rule[lex.a syntax] A.\n") != null);
}

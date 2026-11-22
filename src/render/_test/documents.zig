//! `skein render --format document`, and `--profile`, on a project on
//! disk.

// req: render.documents, render.profiles
const std = @import("std");
const testing = std.testing;

const render = @import("../../commands/render.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn project(dir: std.Io.Dir) !void {
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"srs\"\n");
    try write(dir, ".skein/types/rule.toml", "[attributes.stage]\n");
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n[attributes.stage]\n");
    try write(dir, ".skein/profiles/s0.toml", "[where]\nstage = \"s0\"\n");
    try write(dir, "spec/lex.md",
        \\# Lexical
        \\
        \\Narrative about %[lex.later].
        \\
        \\%rule[lex.now stage=s0] Now; see %[lex.later].
        \\
        \\%rule[lex.later stage=s1] Later, in two lines
        \\of text.
        \\
        \\- %rule[.part stage=s0] A part of later.
        \\
        \\%rule[lex.after stage=s0] After.
        \\
        \\![logo](logo.svg)
        \\
        \\```skein
        \\list rule
        \\```
        \\
    );
    try write(dir, "spec/logo.svg", "<svg/>");
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\nstage = \"s0\"\n+++\n\nNow.\n");
    try write(dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nstage = \"s1\"\n+++\n\nLater.\n");
}

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\n", .{part});
        return error.TestExpectedEqual;
    }
}

fn hasNot(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) != null) {
        std.debug.print("present: {s}\n", .{part});
        return error.TestExpectedEqual;
    }
}

test "a profile leaves out the items outside it, and the links to them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    _ = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = try a.print("{s}/md", .{root}), .profile = "s0" });
    const md = try tmp.dir.readFileAlloc(testing.io, "md/spec/lex.md", a, .limited(1 << 20));
    // the item outside the profile is gone with its lines and its part; a reference to it is its ID
    try hasNot(md, "Later, in two lines");
    try hasNot(md, "of text.");
    try hasNot(md, "A part of later.");
    try has(md, "Narrative about lex.later.");
    try has(md, "**[lex.now](#lex.now)** Now; see lex.later.");
    try has(md, "**[lex.after](#lex.after)** After.");
    // and a generated page is limited to the profile
    try has(md, "| [`lex.now`](#lex.now) |");
    try hasNot(md, "| [`lex.later`]");
    // an item file outside the profile is not written
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "md/requirements/SRS-002.md", .{}));
    try tmp.dir.access(testing.io, "md/requirements/SRS-001.md", .{});

    const outcome = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = "x", .profile = "nope" });
    try testing.expectEqualStrings("skein: there is no profile 'nope'\n", outcome.text);
}

test "each document as one file of its own, its images in it" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try project(tmp.dir);
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", a);

    const out_dir = try a.print("{s}/docs", .{root});
    const outcome = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir, .format = .document });
    try testing.expectEqualStrings(try a.print("skein: 3 documents rendered to {s}\n", .{out_dir}), outcome.text);
    const doc = try tmp.dir.readFileAlloc(testing.io, "docs/spec/lex.html", a, .limited(1 << 20));
    try has(doc, "<title>Lexical</title>");
    try has(doc, "<img src=\"data:image/svg+xml;base64,PHN2Zy8+\" alt=\"logo\">");
    try has(doc, "@media print");
    try hasNot(doc, "<nav");
    // nothing else is written: no site pages, no copies of the images
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "docs/index.html", .{}));
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "docs/spec/logo.svg", .{}));
}

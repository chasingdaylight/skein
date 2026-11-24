//! `skein render --format html`: the static site, on a project on disk.

// req: render.site.pages, render.site.index, render.site.relative
const std = @import("std");
const testing = std.testing;

const render = @import("../../commands/render.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn read(a: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
    return dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
}

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\n", .{part});
        return error.TestExpectedEqual;
    }
}

test "every document and item file is a page, with an index of the items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"srs\"\n");
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, "spec/lex/comments.md", "# Comments\n\nNarrative about %[lex.comment].\n\n%rule[lex.comment syntax see=SRS-001] A comment, as %[SRS-001] asks.\n\n![a picture](pic.svg)\n");
    try write(dir, "spec/lex/pic.svg", "<svg/>");
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\n+++\n\nComments exist; see [the rule](../spec/lex/comments.md#lex.comment).\n");

    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try a.print("{s}/site", .{root});
    const outcome = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir, .format = .html });
    try testing.expectEqualStrings(try a.print("skein: 4 pages rendered to {s}\n", .{out_dir}), outcome.text);

    const doc = try read(a, dir, "site/spec/lex/comments.html");
    try has(doc, "<title>Comments · Example</title>");
    try has(doc, "<h1 id=\"comments\">Comments</h1>");
    try has(doc, "<a id=\"lex.comment\"></a><strong><a href=\"#lex.comment\">lex.comment</a></strong> <em>(syntax)</em> A comment, as <a href=\"../../requirements/SRS-001.html\">SRS-001</a> asks.");
    try has(doc, "Narrative about <a href=\"#lex.comment\">lex.comment</a>.");
    try has(doc, "<img src=\"pic.svg\" alt=\"a picture\">");
    // the navigation, relative to the page
    try has(doc, "<a class=\"brand\" href=\"../../index.html\">Example</a>");
    try has(doc, "<li><a href=\"comments.html\" aria-current=\"page\">Comments</a></li>");
    try has(doc, "<li><a href=\"../../items.html\">All items</a></li>");
    try testing.expectEqualStrings("<svg/>", try read(a, dir, "site/spec/lex/pic.svg"));

    const item = try read(a, dir, "site/requirements/SRS-001.html");
    try has(item, "<h1>SRS-001</h1>");
    try has(item, "<a href=\"../spec/lex/comments.html#lex.comment\">the rule</a>");
    try testing.expect(std.mem.find(u8, item, "title: ") == null);

    const index = try read(a, dir, "site/items.html");
    try has(index, "<tr id=\"lex.comment\"><td><a href=\"spec/lex/comments.html#lex.comment\"><code>lex.comment</code></a></td><td>rule</td><td>syntax</td><td>draft</td><td></td><td>mentioned 1 time</td></tr>");
    try has(index, "<td>see <a href=\"spec/lex/comments.html#lex.comment\"><code>lex.comment</code></a></td><td><a href=\"spec/lex/comments.html#lex.comment\"><code>lex.comment</code></a></td>");

    const front = try read(a, dir, "site/index.html");
    try has(front, "<title>Example</title>");
    try has(front, "<a href=\"spec/lex/comments.html\">Comments</a></td><td><code>spec/lex/comments.md</code>");
    // nothing is loaded from elsewhere
    try testing.expect(std.mem.find(u8, front, "http") == null);
}

// req: render.order
test "a source's item files are in the order of an attribute it names" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"requirements\"\nkind = \"items\"\ntype = \"srs\"\norder_by = \"level\"\n");
    try write(dir, ".skein/types/srs.toml", "id = \"numbered\"\nprefix = \"SRS\"\n[attributes.level]\n");
    try write(dir, "requirements/SRS-001.md", "+++\nid = \"SRS-001\"\nlevel = \"2.10\"\n+++\n\nTen.\n");
    try write(dir, "requirements/SRS-002.md", "+++\nid = \"SRS-002\"\nlevel = \"2.9\"\n+++\n\nNine.\n");
    try write(dir, "requirements/SRS-003.md", "+++\nid = \"SRS-003\"\n+++\n\nNo level.\n");
    try write(dir, "requirements/SRS-004.md", "+++\nid = \"SRS-004\"\nlevel = \"1\"\n+++\n\nOne.\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    _ = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = try a.print("{s}/site", .{root}), .format = .html });
    const front = try read(a, dir, "site/index.html");
    const one = std.mem.find(u8, front, ">SRS-004<").?;
    const nine = std.mem.find(u8, front, ">SRS-002<").?;
    const ten = std.mem.find(u8, front, ">SRS-001<").?;
    const none = std.mem.find(u8, front, ">SRS-003<").?;
    try testing.expect(one < nine and nine < ten and ten < none);
}

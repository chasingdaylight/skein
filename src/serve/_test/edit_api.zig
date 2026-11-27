//! `skein serve`'s editing requests, on a project on disk, without a socket.

// req: serve.edit, serve.check
const std = @import("std");
const testing = std.testing;

const Site = @import("../Site.zig");
const edit_api = @import("../edit_api.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn read(a: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]const u8 {
    return dir.readFileAlloc(testing.io, path, a, .limited(1 << 20));
}

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

const Project = struct {
    tmp: testing.TmpDir,
    site: Site,

    fn deinit(p: *Project) void {
        p.site.deinit();
        p.tmp.cleanup();
    }
};

fn project(a: std.mem.Allocator) !Project {
    const tmp = testing.tmpDir(.{ .iterate = true });
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n[[sources]]\npath = \"std\"\nread_only = true\n");
    try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"static\"]\nstatuses = [\"draft\", \"approved\"]\n");
    try write(dir, ".skein/links/see.toml", "");
    try write(dir, "spec/lex.md", "# Lexing\n\n%rule[lex.comment syntax] A comment.\n\n%rule[lex.space syntax] Spaces.\n");
    try write(dir, "std/base.md", "%rule[std.base syntax] Given.\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    return .{ .tmp = tmp, .site = .init(testing.allocator, testing.io, .{ .common = .{ .root = root } }, dir) };
}

fn get(a: std.mem.Allocator, s: *Site, path: []const u8, query: []const u8) ![]const u8 {
    return (try edit_api.handle(a, s, .get, path, query, "")).body;
}

fn post(a: std.mem.Allocator, s: *Site, path: []const u8, body: []const u8) ![]const u8 {
    return (try edit_api.handle(a, s, .post, path, "", body)).body;
}

test "a page's file, checked as typed and saved unless it changed meanwhile" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var p = try project(a);
    defer p.deinit();
    const s = &p.site;

    const info = try get(a, s, "page", "file=spec%2Flex.md");
    try has(info, "\"editable\":true");
    try has(info, "{\"id\":\"lex.comment\",\"inDocument\":true}");
    try has(info, "\"types\":[\"rule\"]");
    try has(try get(a, s, "page", "file=std/base.md"), "\"editable\":false");

    const source = try get(a, s, "source", "file=spec/lex.md");
    try has(source, "\"text\":\"# Lexing");
    const hash = edit_api.hashOf(try read(a, p.tmp.dir, "spec/lex.md"));
    try has(source, &hash);
    try has(try get(a, s, "source", "file=std/base.md"), "is in the read-only source 'std'");
    try has(try get(a, s, "source", "file=../x.md"), "is not a file of the project's sources");

    // what check finds in the text as typed, not saved
    const checked = try post(a, s, "check", "{\"file\":\"spec/lex.md\",\"text\":\"%rule[lex.comment] See %[lex.none].\\n\"}");
    try has(checked, "\"message\":\"lex.comment: an item of type 'rule' needs a category\"");
    try has(checked, "the text refers to 'lex.none'");
    try has(try read(a, p.tmp.dir, "spec/lex.md"), "A comment.");

    const new_text = "# Lexing\n\n%rule[lex.comment syntax] A comment, said again.\n";
    try has(try post(a, s, "source", try a.print("{{\"file\":\"spec/lex.md\",\"text\":\"{s}\",\"hash\":\"{s}\"}}", .{ "# Lexing\\n\\n%rule[lex.comment syntax] A comment, said again.\\n", &hash })), "\"file\":\"spec/lex.md\"");
    try testing.expectEqualStrings(new_text, try read(a, p.tmp.dir, "spec/lex.md"));
    // the same hash again: the file changed since
    try has(try post(a, s, "source", try a.print("{{\"file\":\"spec/lex.md\",\"text\":\"x\",\"hash\":\"{s}\"}}", .{&hash})), "changed since this page read it");
    try testing.expectEqualStrings(new_text, try read(a, p.tmp.dir, "spec/lex.md"));
}

test "an item's form, previewed and saved" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var p = try project(a);
    defer p.deinit();
    const s = &p.site;

    const form = try get(a, s, "form", "id=lex.space");
    try has(form, "\"statuses\":[\"draft\",\"approved\"]");
    try has(form, "\"category\":\"syntax\"");
    const hash = edit_api.hashOf(try read(a, p.tmp.dir, "spec/lex.md"));
    try has(form, &hash);
    try has(try get(a, s, "form", "id=lex.none"), "there is no item 'lex.none'");

    try has(try post(a, s, "preview", "{\"id\":\"lex.space\",\"type\":\"rule\",\"status\":\"done\"}"), "'done' is not a status of a 'rule'");
    try has(try post(a, s, "preview", "{\"id\":\"lex.space\",\"type\":\"rule\",\"category\":\"static\",\"links\":{\"see\":[\"lex.comment\"]}}"), "\"problems\":[]");

    const saved = try post(a, s, "save", try a.print("{{\"id\":\"lex.space\",\"type\":\"rule\",\"category\":\"static\",\"status\":\"draft\",\"links\":{{\"see\":[\"lex.comment\"]}},\"hash\":\"{s}\"}}", .{&hash}));
    try has(saved, "\"id\":\"lex.space\"");
    try has(try read(a, p.tmp.dir, "spec/lex.md"), "%rule[lex.space static draft see=lex.comment] Spaces.");
    // the form was read before that save
    try has(try post(a, s, "save", try a.print("{{\"id\":\"lex.space\",\"type\":\"rule\",\"status\":\"approved\",\"hash\":\"{s}\"}}", .{&hash})), "changed since this page read it");

    const new = try post(a, s, "save", "{\"new\":true,\"id\":\"lex.tab\",\"type\":\"rule\",\"category\":\"syntax\",\"document\":\"spec/lex.md\",\"text\":\"Tabs.\"}");
    try has(new, "\"id\":\"lex.tab\"");
    try has(try read(a, p.tmp.dir, "spec/lex.md"), "%rule[lex.tab syntax] Tabs.");
    try has(try post(a, s, "save", "{\"id\":\"std.base\",\"type\":\"rule\",\"category\":\"static\",\"hash\":\"\"}"), "read-only");
}

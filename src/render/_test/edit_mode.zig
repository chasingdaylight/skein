//! `skein render --format html --edit --wasm FILE`, and `skein api`, which
//! its pages ask, on a project on disk.

// req: serve.static-edit, serve.static-forge
const std = @import("std");
const testing = std.testing;

const api = @import("../../commands/api.zig");
const cli = @import("../../cli.zig");
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
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

test "the site's pages carry skein for WebAssembly and the project's files" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n");
    try write(dir, ".skein/types/rule.toml", "");
    try write(dir, "spec/lex/comments.md", "# Comments\n\n%rule[lex.comment] A comment.\n");
    try write(dir, "spec/lex/pic.png", "\x89PNG\x00\xff");
    // a module's header is all render looks at
    try write(dir, "skein.wasm", "\x00asm\x01\x00\x00\x00");
    try write(dir, "not.wasm", "text");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const out_dir = try a.print("{s}/site", .{root});
    const wasm = try a.print("{s}/skein.wasm", .{root});

    const outcome = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir, .format = .html, .wasm = wasm });
    try testing.expectEqual(.ok, outcome.status);
    try has(outcome.text, "the pages edit 3 files, with skein for WebAssembly");
    try testing.expectEqualStrings("\x00asm\x01\x00\x00\x00", try read(a, dir, "site/_skein/skein.wasm"));
    for ([_][]const u8{ "wasi.js", "static.js", "edit.js" }) |f| _ = try read(a, dir, try a.print("site/_skein/{s}", .{f}));
    const carried = try read(a, dir, "site/_skein/files.json");
    try has(carried, "\".skein/config.toml\":\"[project]\\nname = \\\"Example\\\"");
    try has(carried, "\"spec/lex/comments.md\":\"# Comments");
    // what is not text is left out
    try testing.expect(std.mem.find(u8, carried, "pic.png") == null);
    try has(try read(a, dir, "site/spec/lex/comments.html"), "<script src=\"../../_skein/edit.js\"></script>\n</body>");
    try has(try read(a, dir, "site/index.html"), "<script src=\"_skein/static.js\"></script>");

    const refused = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = out_dir, .format = .html, .wasm = try a.print("{s}/not.wasm", .{root}) });
    try has(refused.text, "is not a WebAssembly module");
    try has((try cli.parse(a, &.{ "render", "--out", "x", "--edit" })).misuse, "render --edit: with --format html, and --wasm FILE");

    // what the pages ask: here of the program built for this computer
    const info = try api.run(testing.io, testing.allocator, a, .{ .common = .{ .root = root }, .method = .get, .path = "page", .query = "file=spec/lex/comments.md" });
    try has(info.text, "{\"editable\":true,\"items\":[{\"id\":\"lex.comment\",\"inDocument\":true}]");
    try has((try cli.parse(a, &.{ "api", "PUT", "page" })).misuse, "api: GET or POST");
}

test "where the project names its forge, the site says where its changes are saved" {
    const Repo = @import("../../commands/_test/Repo.zig");
    var repo: Repo = undefined;
    try repo.init();
    defer repo.deinit();
    const a = repo.arena.allocator();
    // the project in a directory of the repository, saving by commit to dev
    try repo.write("req/.skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n[forge]\nkind = \"gitlab\"\nrepository = \"group/spec\"\nurl = \"https://gitlab.example.com\"\n[serve]\nsave = \"commit\"\nbranch = \"dev\"\n");
    try repo.write("req/.skein/types/rule.toml", "");
    try repo.write("req/spec/a.md", "%rule[a.b] A.\n");
    try repo.write("skein.wasm", "\x00asm\x01\x00\x00\x00");
    try repo.commit("a project below the top");
    const root = try std.Io.Dir.path.join(a, &.{ repo.root, "req" });
    const out = try render.run(testing.io, a, .{ .common = .{ .root = root }, .out = try std.Io.Dir.path.join(a, &.{ repo.root, "site" }), .format = .html, .wasm = try std.Io.Dir.path.join(a, &.{ repo.root, "skein.wasm" }) });
    try testing.expectEqual(.ok, out.status);
    try testing.expectEqualStrings(
        "{\"kind\":\"gitlab\",\"repository\":\"group/spec\",\"url\":\"https://gitlab.example.com\",\"api\":\"https://gitlab.example.com/api/v4\",\"branch\":\"dev\",\"prefix\":\"req/\",\"save\":\"commit\"}",
        try read(a, repo.tmp.dir, "site/_skein/forge.json"),
    );
    try has(try read(a, repo.tmp.dir, "site/spec/a.html"), "<script src=\"../_skein/forge.js\"></script>");
}

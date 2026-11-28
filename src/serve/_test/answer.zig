//! `skein serve`'s answers, on a project on disk, without a socket.

// req: serve.site
const std = @import("std");
const testing = std.testing;

const Site = @import("../Site.zig");
const answer = @import("../answer.zig");

fn write(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    if (std.Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

fn has(text: []const u8, part: []const u8) !void {
    if (std.mem.find(u8, text, part) == null) {
        std.debug.print("missing: {s}\nin: {s}\n", .{ part, text });
        return error.TestExpectedEqual;
    }
}

test "the site's pages, rendered again when the files change" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project]\nname = \"Example\"\n[[sources]]\npath = \"spec\"\n");
    try write(dir, ".skein/types/rule.toml", "");
    try write(dir, "spec/lex/comments.md", "# Comments\n\n%rule[lex.comment] A comment.\n");
    try write(dir, "spec/lex/pic.svg", "<svg/>");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);

    var s: Site = .init(testing.allocator, testing.io, .{ .common = .{ .root = root } }, dir);
    defer s.deinit();

    const front = try answer.get(a, &s, "/");
    try testing.expectEqual(.ok, front.status);
    try has(front.body, "<title>Example</title>");
    // the page asks for the stamp it was rendered from
    try has(front.body, try a.print("var s=\"{s}\";", .{&s.stamp}));
    try has(front.body, "</script>\n</body>");

    const page = try answer.get(a, &s, "/spec/lex/comments.html?x=1");
    try has(page.body, "A comment.");
    const svg = try answer.get(a, &s, "/spec/lex/pic.svg");
    try testing.expectEqualStrings("image/svg+xml", svg.content_type);
    try testing.expectEqualStrings("<svg/>", svg.body);
    try testing.expectEqual(.not_found, (try answer.get(a, &s, "/spec/none.html")).status);
    try testing.expectEqual(.not_found, (try answer.get(a, &s, "/spec/%zz")).status);

    const before = try answer.get(a, &s, answer.stamp_path);
    try testing.expectEqualStrings(&s.stamp, before.body);
    try write(dir, "spec/lex/comments.md", "# Comments\n\n%rule[lex.comment] A comment, changed.\n");
    // the asks of one second share one look at the files
    s.checked_at = std.Io.Clock.real.now(testing.io).toSeconds();
    try testing.expectEqualStrings(before.body, (try answer.get(a, &s, answer.stamp_path)).body);
    // and the next second looks again
    s.checked_at -= 1;
    const after = try answer.get(a, &s, answer.stamp_path);
    try testing.expect(!std.mem.eql(u8, before.body, after.body));
    try has((try answer.get(a, &s, "/spec/lex/comments.html")).body, "A comment, changed.");
    try testing.expectEqualStrings(after.body, &s.stamp);
}

test "a configuration with problems is a page that says them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = tmp.dir;
    try write(dir, ".skein/config.toml", "[project\n");
    const root = try dir.realPathFileAlloc(testing.io, ".", a);

    var s: Site = .init(testing.allocator, testing.io, .{ .common = .{ .root = root } }, dir);
    defer s.deinit();
    const page = try answer.get(a, &s, "/");
    try testing.expectEqual(.service_unavailable, page.status);
    try has(page.body, "The site cannot be rendered");
    try has(page.body, "config.toml");

    try write(dir, ".skein/config.toml", "[project]\nname = \"Fixed\"\n");
    try has((try answer.get(a, &s, "/")).body, "Fixed");
}

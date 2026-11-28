//! The projects the language server finds: in the editor's folders, below
//! them, and above each document.

// req: lsp.projects
const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const json = std.json;

const Server = @import("../Server.zig");
const discovery = @import("../projects.zig");
const jsonrpc = @import("../jsonrpc.zig");
const uri_paths = @import("../uri.zig");

fn write(dir: Io.Dir, path: []const u8, data: []const u8) !void {
    if (Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

/// A project named `name` at `at`, with one document holding a reference
/// to an item there is not
fn project(dir: Io.Dir, comptime at: []const u8, comptime name: []const u8) !void {
    try write(dir, at ++ "/.skein/config.toml", "[project]\nname = \"" ++ name ++ "\"\n[[sources]]\npath = \"spec\"\n");
    try write(dir, at ++ "/.skein/types/rule.toml", "");
    try write(dir, at ++ "/spec/a.md", "%rule[" ++ name ++ ".one] See %[" ++ name ++ ".gone].\n");
}

/// The project the temporary directory is, so that the search upward from
/// a folder in it stops there (it is inside skein's own checkout)
fn outer(dir: Io.Dir) !void {
    try write(dir, ".skein/config.toml", "[project]\nname = \"outer\"\n");
}

fn freeAll(list: *std.ArrayList([]u8)) void {
    for (list.items) |r| testing.allocator.free(r);
    list.deinit(testing.allocator);
}

test "projects are found in a folder and below it, not in caches or too deep" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    try outer(dir);
    try project(dir, "top/one", "one");
    try project(dir, "top/x/y/two", "two");
    try project(dir, "top/node_modules/pkg", "skipped");
    try project(dir, "top/.hidden/p", "hidden");
    try project(dir, "top/a/b/c/d/deep", "deep");
    try write(dir, "top/notes.md", "");
    const top = try dir.realPathFileAlloc(testing.io, "top", a);

    var found: std.ArrayList([]u8) = .empty;
    defer freeAll(&found);
    try discovery.discover(testing.io, testing.allocator, &.{top}, &found);
    // the project the folder is in, then those inside it
    try testing.expectEqual(3, found.items.len);
    try testing.expectEqualStrings(try dir.realPathFileAlloc(testing.io, ".", a), found.items[0]);
    try testing.expect(std.mem.endsWith(u8, found.items[1], "one"));
    try testing.expect(std.mem.endsWith(u8, found.items[2], "two"));

    // a folder inside a project: that project, once
    const inner = try dir.realPathFileAlloc(testing.io, "top/one/spec", a);
    try discovery.discover(testing.io, testing.allocator, &.{ inner, top }, &found);
    try testing.expectEqual(3, found.items.len);

    // a file's project is the nearest above it
    const file = try dir.realPathFileAlloc(testing.io, "top/x/y/two/spec/a.md", a);
    try testing.expect(std.mem.endsWith(u8, discovery.rootOf(testing.io, a, file).?, "two"));
    try testing.expectEqualStrings(found.items[0], discovery.rootOf(testing.io, a, try dir.realPathFileAlloc(testing.io, "top/notes.md", a)).?);
}

/// Sends a message to the server and returns what it sent, parsed
fn send(server: *Server, out: *Io.Writer.Allocating, a: std.mem.Allocator, body: []const u8) ![]const json.Value {
    out.clearRetainingCapacity();
    try server.handle(a, body);
    var reader: Io.Reader = .fixed(out.written());
    var messages: std.ArrayList(json.Value) = .empty;
    while (try jsonrpc.readMessage(a, &reader)) |m| try messages.append(a, try json.parseFromSliceLeaky(json.Value, a, m, .{}));
    return messages.items;
}

test "the server serves every project of the editor's folders" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = tmp.dir;
    // the first folder is no project, but has one inside it
    try outer(dir);
    try write(dir, "first/readme.md", "Not a project.\n");
    try project(dir, "first/inner", "inner");
    try project(dir, "second", "second");
    try project(dir, "elsewhere", "elsewhere");
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var server: Server = .{ .gpa = testing.allocator, .io = testing.io, .out = &out.writer, .version = "test" };
    defer server.deinit();
    const style = server.style;
    const uri = struct {
        fn of(al: std.mem.Allocator, d: Io.Dir, path: []const u8, st: uri_paths.Style) ![]const u8 {
            return uri_paths.fromPath(al, try d.realPathFileAlloc(testing.io, path, al), st);
        }
    }.of;
    const first = try uri(a, dir, "first", style);
    const second = try uri(a, dir, "second", style);

    _ = try send(&server, &out, a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"rootUri\":\"{s}\",\"workspaceFolders\":[{{\"uri\":\"{s}\",\"name\":\"first\"}},{{\"uri\":\"{s}\",\"name\":\"second\"}}]}}}}", .{ first, first, second }));
    const published = try send(&server, &out, a, "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
    // a problem in each project (the outer one has none)
    try testing.expectEqual(2, published.len);
    const inner_doc = try uri(a, dir, "first/inner/spec/a.md", style);
    const second_doc = try uri(a, dir, "second/spec/a.md", style);
    try testing.expectEqualStrings(inner_doc, published[0].object.get("params").?.object.get("uri").?.string);
    try testing.expectEqualStrings(second_doc, published[1].object.get("params").?.object.get("uri").?.string);

    const listed = try send(&server, &out, a, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"skein/projects\"}");
    const list = listed[0].object.get("result").?.array.items;
    try testing.expectEqual(3, list.len);
    try testing.expectEqualStrings("outer", list[0].object.get("name").?.string);
    try testing.expectEqualStrings("inner", list[1].object.get("name").?.string);
    try testing.expectEqualStrings("second", list[2].object.get("name").?.string);

    // a document's request is about its own project
    const rendered = try send(&server, &out, a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"skein/render\",\"params\":{{\"uri\":\"{s}\"}}}}", .{second_doc}));
    try testing.expect(std.mem.find(u8, rendered[0].object.get("result").?.object.get("rendered").?.string, "second.one") != null);
    // one that names none: the first project, or the one it names
    const items = try send(&server, &out, a, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"skein/items\"}");
    try testing.expectEqualStrings("outer", items[0].object.get("result").?.object.get("project").?.string);
    const named = try send(&server, &out, a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"skein/items\",\"params\":{{\"project\":\"{s}\"}}}}", .{second}));
    try testing.expectEqualStrings("second", named[0].object.get("result").?.object.get("project").?.string);

    // a document of a project outside the folders: its project too, from then on
    const other_doc = try uri(a, dir, "elsewhere/spec/a.md", style);
    const opened = try send(&server, &out, a, try a.print("{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"text\":\"\"}}}}}}", .{other_doc}));
    try testing.expectEqual(3, opened.len);
    try testing.expectEqualStrings(other_doc, opened[2].object.get("params").?.object.get("uri").?.string);

    // a folder closed: its projects go, and their problems are cleared
    const closed = try send(&server, &out, a, try a.print("{{\"jsonrpc\":\"2.0\",\"method\":\"workspace/didChangeWorkspaceFolders\",\"params\":{{\"event\":{{\"added\":[],\"removed\":[{{\"uri\":\"{s}\",\"name\":\"first\"}}]}}}}}}", .{first}));
    try testing.expectEqual(3, closed.len);
    try testing.expectEqualStrings(inner_doc, closed[0].object.get("params").?.object.get("uri").?.string);
    try testing.expectEqual(0, closed[0].object.get("params").?.object.get("diagnostics").?.array.items.len);
    const after = try send(&server, &out, a, "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"skein/projects\"}");
    try testing.expectEqual(2, after[0].object.get("result").?.array.items.len);
}

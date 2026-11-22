//! The requests of the editor's views, code lenses and quick fixes, on a
//! project on disk.

// req: lsp.items, lsp.views, lsp.lens, lsp.fixes
// cspell:ignore syntx tokn verifes
const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const json = std.json;

const Server = @import("../Server.zig");
const jsonrpc = @import("../jsonrpc.zig");
const uri_paths = @import("../uri.zig");

fn write(dir: Io.Dir, path: []const u8, data: []const u8) !void {
    if (Io.Dir.path.dirname(path)) |parent| try dir.createDirPath(testing.io, parent);
    try dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

const lex =
    \\# Lexical structure
    \\
    \\%rule[lex.token syntx] A token, the smallest unit.
    \\
    \\%rule[lex.keywords syntax] The keywords, see %[lex.tokn].
    \\
    \\%case[c.one verifies=lex.token] Checks.
    \\
    \\%case[c.two verifes=lex.keywords] Checks more.
    \\
    \\%case[c.three verifies=lex.old] Checks the renamed.
    \\
;

const Session = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    out: Io.Writer.Allocating,
    server: Server,
    root: []const u8,
    next_id: i64 = 1,

    fn init(self: *Session) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.out = .init(testing.allocator);
        self.next_id = 1;
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", "[project]\nname = \"example\"\n[[sources]]\npath = \"spec\"\n");
        try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\"]\n");
        try write(dir, ".skein/types/case.toml", "");
        try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\nexpected = true\n");
        try write(dir, "spec/lex.md", lex);
        try write(dir, "spec/old.md", "%rule[lex.renamed syntax aliases=lex.old] Renamed.\n");
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.server = .{ .gpa = testing.allocator, .io = testing.io, .out = &self.out.writer, .version = "test" };
        _ = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"rootUri\":\"{s}\"}}}}", .{try self.uri("")});
    }

    fn deinit(self: *Session) void {
        self.server.deinit();
        self.out.deinit();
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn uri(self: *Session, file: []const u8) ![]const u8 {
        const a = self.arena.allocator();
        return uri_paths.fromPath(a, try Io.Dir.path.join(a, &.{ self.root, file }), self.server.style);
    }

    fn send(self: *Session, comptime fmt: []const u8, args: anytype) ![]const json.Value {
        const a = self.arena.allocator();
        self.out.clearRetainingCapacity();
        try self.server.handle(a, try a.print(fmt, args));
        var reader: Io.Reader = .fixed(self.out.written());
        var messages: std.ArrayList(json.Value) = .empty;
        while (try jsonrpc.readMessage(a, &reader)) |body| {
            try messages.append(a, try json.parseFromSliceLeaky(json.Value, a, body, .{}));
        }
        return messages.items;
    }

    /// The result of the request `method` with `params` (JSON)
    fn request(self: *Session, method: []const u8, params: []const u8) !json.Value {
        self.next_id += 1;
        const answer = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{s}}}", .{ self.next_id, method, params });
        try testing.expectEqual(1, answer.len);
        return answer[0].object.get("result") orelse answer[0].object.get("error").?;
    }

    /// The diagnostics published for `spec/lex.md`
    fn diagnostics(self: *Session) ![]const json.Value {
        for (try self.send("{{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{{}}}}", .{})) |m| {
            const params = m.object.get("params").?.object;
            if (std.mem.eql(u8, params.get("uri").?.string, try self.uri("spec/lex.md"))) return params.get("diagnostics").?.array.items;
        }
        return error.TestUnexpectedResult;
    }
};

fn get(v: json.Value, name: []const u8) json.Value {
    return v.object.get(name).?;
}

test "skein/items: every item with its place, for the tree" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const result = try s.request("skein/items", "{}");
    try testing.expectEqualStrings("example", get(result, "project").string);
    try testing.expectEqualStrings("spec", get(result, "sources").array.items[0].string);
    const items = get(result, "items").array.items;
    try testing.expectEqual(6, items.len);
    try testing.expectEqualStrings("lex.token", get(items[0], "id").string);
    try testing.expectEqualStrings("rule", get(items[0], "type").string);
    try testing.expectEqualStrings("spec/lex.md", get(items[0], "file").string);
    try testing.expectEqual(2, get(items[0], "line").integer);
    try testing.expectEqualStrings("A token, the smallest unit.", get(items[0], "title").string);
    try testing.expectEqualStrings("spec", get(items[0], "source").string);
    try testing.expectEqualStrings(try s.uri("spec/lex.md"), get(items[0], "uri").string);
}

test "skein/itemAt, skein/trace and skein/coverage" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const a = s.arena.allocator();
    const at = try s.request("skein/itemAt", try a.print("{{\"textDocument\":{{\"uri\":\"{s}\"}},\"position\":{{\"line\":6,\"character\":3}}}}", .{try s.uri("spec/lex.md")}));
    try testing.expectEqualStrings("c.one", get(at, "id").string);

    const traced = get(try s.request("skein/trace", "{\"id\":\"lex.token\"}"), "html").string;
    try testing.expect(std.mem.find(u8, traced, "<h1") != null);
    try testing.expect(std.mem.find(u8, traced, "href=\"skein:item/c.one\"") != null);
    try testing.expect(std.mem.find(u8, traced, "href=\"skein:file/spec/lex.md#3\"") != null);
    // a former ID finds the item it names now
    try testing.expectEqualStrings("lex.renamed", get(try s.request("skein/trace", "{\"id\":\"lex.old\"}"), "id").string);
    try testing.expect(get(try s.request("skein/trace", "{\"id\":\"no.such\"}"), "message").string.len > 0);

    const covered = try s.request("skein/coverage", "{}");
    // lex.token is verified, and lex.renamed by its former ID; lex.keywords
    // is not (its link is misspelled)
    try testing.expectEqual(2, get(covered, "covered").integer);
    try testing.expectEqual(3, get(covered, "total").integer);
    try testing.expect(std.mem.find(u8, get(covered, "html").string, "href=\"skein:item/lex.keywords\"") != null);
}

test "code lenses: an item's links, and Trace" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const a = s.arena.allocator();
    const lenses = (try s.request("textDocument/codeLens", try a.print("{{\"textDocument\":{{\"uri\":\"{s}\"}}}}", .{try s.uri("spec/lex.md")}))).array.items;
    // "Trace" for each of the five items of the file, and the links of the
    // three that have any (c.two's misspelled link is none)
    try testing.expectEqual(8, lenses.len);
    const links = get(lenses[0], "command");
    try testing.expectEqualStrings("verifies from c.one", get(links, "title").string);
    try testing.expectEqualStrings("skein.pickLinked", get(links, "command").string);
    const choices = get(links, "arguments").array.items[1].array.items;
    try testing.expectEqualStrings("c.one", get(choices[0], "id").string);
    try testing.expectEqual(2, get(get(lenses[0], "range"), "start").object.get("line").?.integer);
    try testing.expectEqualStrings("Trace", get(get(lenses[1], "command"), "title").string);
    try testing.expectEqualStrings("lex.token", get(get(lenses[1], "command"), "arguments").array.items[0].string);
    // lex.keywords: Trace alone
    try testing.expectEqualStrings("lex.keywords", get(get(lenses[2], "command"), "arguments").array.items[0].string);
    try testing.expectEqualStrings("verifies lex.token", get(get(lenses[3], "command"), "title").string);
}

/// The quick fixes offered for the problems of `spec/lex.md`, as "title
/// line:character new text", sorted
fn quickFixes(s: *Session) ![]const []const u8 {
    const a = s.arena.allocator();
    const diagnostics = try s.diagnostics();
    var fixes: std.ArrayList([]const u8) = .empty;
    for (diagnostics) |d| {
        const params = try a.print("{{\"textDocument\":{{\"uri\":\"{s}\"}},\"range\":{f},\"context\":{{\"diagnostics\":[{f}]}}}}", .{ try s.uri("spec/lex.md"), json.fmt(get(d, "range"), .{}), json.fmt(d, .{}) });
        for ((try s.request("textDocument/codeAction", params)).array.items) |action| {
            const edit = get(get(action, "edit"), "changes").object.get(try s.uri("spec/lex.md")).?.array.items[0];
            try fixes.append(a, try a.print("{s} {d}:{d} {s}", .{ get(action, "title").string, get(get(get(edit, "range"), "start"), "line").integer, get(get(get(edit, "range"), "start"), "character").integer, get(edit, "newText").string }));
        }
    }
    std.mem.sort([]const u8, fixes.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.lt);
    return fixes.items;
}

fn expectFixes(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "quick fixes: the word meant, and the ID an item has now" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    // a marker that cannot be read stops the rest being checked
    try expectFixes(&.{"Write 'syntax' for 'syntx' 2:16 syntax"}, try quickFixes(&s));
    try write(s.tmp.dir, "spec/lex.md", try std.mem.replaceOwned(u8, s.arena.allocator(), lex, "syntx", "syntax"));
    try expectFixes(&.{
        "Write 'lex.renamed' for 'lex.old' 10:23 lex.renamed",
        "Write 'lex.token' for 'lex.tokn' 4:47 lex.token",
        "Write 'verifies' for 'verifes' 8:12 verifies",
    }, try quickFixes(&s));
}

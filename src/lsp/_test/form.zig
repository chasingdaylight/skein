//! The requests of the item forms: what a form shows, and a form written
//! into a marker, into front matter, and as a new item.

// req: lsp.forms, edit.vscode
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

const Session = struct {
    arena: std.heap.ArenaAllocator,
    tmp: testing.TmpDir,
    out: Io.Writer.Allocating,
    server: Server,
    next_id: i64 = 1,

    fn init(self: *Session) !void {
        self.arena = .init(testing.allocator);
        self.tmp = testing.tmpDir(.{});
        self.out = .init(testing.allocator);
        self.next_id = 1;
        const dir = self.tmp.dir;
        try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n\n[[sources]]\npath = \"needs\"\nkind = \"items\"\ntype = \"req\"\n");
        try write(dir, ".skein/types/rule.toml", "categories = [\"syntax\", \"legality\"]\n[attributes.stage]\nvalues = [\"s0\", \"s1\"]\n");
        try write(dir, ".skein/types/req.toml", "id = \"numbered\"\nprefix = \"REQ\"\n[attributes.priority]\ntype = \"integer\"\n");
        try write(dir, ".skein/links/refines.toml", "to = [\"req\"]\n");
        try write(dir, "spec/lex.md", "# Lexical\n\n%rule[lex.token syntax stage=s0] A token.\n");
        try write(dir, "needs/REQ-001.md", "+++\nid = \"REQ-001\"\n+++\n\nThe first.\n");
        const root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.server = .{ .gpa = testing.allocator, .io = testing.io, .out = &self.out.writer, .version = "test" };
        const a = self.arena.allocator();
        _ = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"rootUri\":\"{s}\"}}}}", .{try uri_paths.fromPath(a, try Io.Dir.path.join(a, &.{ root, "" }), self.server.style)});
    }

    fn deinit(self: *Session) void {
        self.server.deinit();
        self.out.deinit();
        self.tmp.cleanup();
        self.arena.deinit();
    }

    fn send(self: *Session, comptime fmt: []const u8, args: anytype) ![]const json.Value {
        const a = self.arena.allocator();
        self.out.clearRetainingCapacity();
        try self.server.handle(a, try a.print(fmt, args));
        var reader: Io.Reader = .fixed(self.out.written());
        var messages: std.ArrayList(json.Value) = .empty;
        while (try jsonrpc.readMessage(a, &reader)) |body| try messages.append(a, try json.parseFromSliceLeaky(json.Value, a, body, .{}));
        return messages.items;
    }

    fn request(self: *Session, method: []const u8, params: []const u8) !json.Value {
        self.next_id += 1;
        for (try self.send("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{s}}}", .{ self.next_id, method, params })) |m| {
            if (m.object.get("id") != null) return m.object.get("result") orelse m.object.get("error").?;
        }
        return error.TestUnexpectedResult;
    }

    fn read(self: *Session, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

fn get(v: json.Value, name: []const u8) json.Value {
    return v.object.get(name).?;
}

test "skein/form: the item and what its type allows" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const f = try s.request("skein/form", "{\"id\":\"lex.token\"}");
    try testing.expectEqualStrings("syntax", get(get(f, "item"), "category").string);
    try testing.expectEqualStrings("s0", get(get(get(f, "item"), "attributes"), "stage").string);
    const t = get(f, "type");
    try testing.expectEqual(2, get(t, "categories").array.items.len);
    try testing.expectEqualStrings("stage", get(get(t, "attributes").array.items[0], "name").string);
    const link = get(t, "links").array.items[0];
    try testing.expectEqualStrings("refines", get(link, "name").string);
    try testing.expectEqualStrings("REQ-001", get(link, "targets").array.items[0].string);
    try testing.expectEqualStrings("spec/lex.md", get(f, "documents").array.items[0].string);
    // a new req goes into a file of its own
    try testing.expect(get(try s.request("skein/form", "{\"type\":\"req\"}"), "itemFiles").bool);
}

test "skein/saveItem: a marker, front matter, and new items" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    // the marker: another category, a status, a value taken out, a link added
    _ = try s.request("skein/saveItem", "{\"id\":\"lex.token\",\"type\":\"rule\",\"category\":\"legality\",\"status\":\"approved\",\"attributes\":{\"stage\":\"\"},\"links\":{\"refines\":[\"REQ-001\"]}}");
    try testing.expectEqualStrings("# Lexical\n\n%rule[lex.token legality approved refines=REQ-001] A token.\n", try s.read("spec/lex.md"));
    // front matter
    _ = try s.request("skein/saveItem", "{\"id\":\"REQ-001\",\"type\":\"req\",\"status\":\"approved\",\"attributes\":{\"priority\":\"2\"}}");
    try testing.expectEqualStrings("+++\nid = \"REQ-001\"\npriority = 2\nstatus = \"approved\"\n+++\n\nThe first.\n", try s.read("needs/REQ-001.md"));
    // a new req: the next number, in a file of its own, with its text
    const made = try s.request("skein/saveItem", "{\"new\":true,\"type\":\"req\",\"text\":\"The second.\",\"attributes\":{\"priority\":\"1\"}}");
    try testing.expectEqualStrings("REQ-002", get(made, "id").string);
    const second = try s.read("needs/REQ-002.md");
    try testing.expect(std.mem.find(u8, second, "priority = 1") != null);
    try testing.expect(std.mem.endsWith(u8, second, "The second.\n"));
    // a new rule, at the end of the document chosen
    _ = try s.request("skein/saveItem", "{\"new\":true,\"id\":\"lex.space\",\"type\":\"rule\",\"category\":\"syntax\",\"document\":\"spec/lex.md\",\"text\":\"White space.\"}");
    try testing.expect(std.mem.endsWith(u8, try s.read("spec/lex.md"), "\n\n%rule[lex.space syntax] White space.\n"));
    // what check would refuse is refused
    try testing.expectEqualStrings("skein: 'odd' is not a category of a 'rule'", get(try s.request("skein/saveItem", "{\"id\":\"lex.token\",\"type\":\"rule\",\"category\":\"odd\"}"), "message").string);
}

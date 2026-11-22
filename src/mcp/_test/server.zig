//! The Model Context Protocol server, given messages as an agent sends
//! them, on a project on disk.

// req: mcp.protocol, mcp.tools
const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const json = std.json;

const Server = @import("../Server.zig");

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
        try write(dir, ".skein/config.toml", "[[sources]]\npath = \"spec\"\n");
        try write(dir, ".skein/types/rule.toml", "description = \"A rule\"\n");
        try write(dir, ".skein/types/case.toml", "");
        try write(dir, ".skein/links/verifies.toml", "from = [\"case\"]\nto = [\"rule\"]\nexpected = true\n");
        try write(dir, "spec/lex.md", "%rule[lex.token] A token.\n\n%rule[lex.space] White space.\n\n%case[c.one verifies=lex.token] Checks.\n");
        const root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.server = .{ .io = testing.io, .out = &self.out.writer, .version = "test", .root = root };
    }

    fn deinit(self: *Session) void {
        self.out.deinit();
        self.tmp.cleanup();
        self.arena.deinit();
    }

    /// The lines the server wrote for a message, parsed
    fn send(self: *Session, line: []const u8) ![]const json.Value {
        const a = self.arena.allocator();
        self.out.clearRetainingCapacity();
        try self.server.handle(a, line);
        var out: std.ArrayList(json.Value) = .empty;
        var lines = std.mem.tokenizeScalar(u8, self.out.written(), '\n');
        while (lines.next()) |l| try out.append(a, try json.parseFromSliceLeaky(json.Value, a, try a.dupe(u8, l), .{}));
        return out.items;
    }

    fn call(self: *Session, tool: []const u8, args: []const u8) !json.Value {
        const a = self.arena.allocator();
        self.next_id += 1;
        const answer = try self.send(try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"tools/call\",\"params\":{{\"name\":\"{s}\",\"arguments\":{s}}}}}", .{ self.next_id, tool, args }));
        try testing.expectEqual(1, answer.len);
        return answer[0].object.get("result").?;
    }
};

fn get(v: json.Value, name: []const u8) json.Value {
    return v.object.get(name).?;
}

/// The JSON a tool answered with, parsed
fn content(s: *Session, result: json.Value) !json.Value {
    const text = get(get(result, "content").array.items[0], "text").string;
    return json.parseFromSliceLeaky(json.Value, s.arena.allocator(), text, .{});
}

test "initialize, the tools, notifications and what is not known" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const init = (try s.send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{}}}"))[0];
    const result = get(init, "result");
    try testing.expectEqualStrings("2025-03-26", get(result, "protocolVersion").string);
    try testing.expectEqualStrings("skein", get(get(result, "serverInfo"), "name").string);
    try testing.expect(get(get(result, "capabilities"), "tools") == .object);
    // a version skein does not know: its newest
    try testing.expectEqualStrings("2025-06-18", get(get((try s.send("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"1999-01-01\"}}"))[0], "result"), "protocolVersion").string);
    try testing.expectEqual(0, (try s.send("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")).len);

    const tools = get(get((try s.send("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}"))[0], "result"), "tools").array.items;
    try testing.expectEqual(10, tools.len);
    try testing.expectEqualStrings("items", get(tools[0], "name").string);
    try testing.expectEqualStrings("object", get(get(tools[1], "inputSchema"), "type").string);

    try testing.expectEqual(-32601, get(get((try s.send("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"resources/list\"}"))[0], "error"), "code").integer);
    try testing.expectEqual(-32700, get(get((try s.send("not json"))[0], "error"), "code").integer);
}

test "the tools: items, trace, check, coverage, and an edit" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const found = try content(&s, try s.call("items", "{\"query\":\"white\"}"));
    try testing.expectEqual(1, found.array.items.len);
    try testing.expectEqualStrings("lex.space", get(found.array.items[0], "id").string);

    const traced = try content(&s, try s.call("trace", "{\"id\":\"lex.token\"}"));
    try testing.expectEqualStrings("lex.token", get(get(traced, "item"), "id").string);

    const checked = try content(&s, try s.call("check", "{}"));
    try testing.expect(get(checked, "ok").bool);

    const covered = try content(&s, try s.call("coverage", "{}"));
    try testing.expect(get(covered, "expectations") == .array);

    // an edit, and then check sees it
    const linked = try s.call("link", "{\"from\":\"c.one\",\"type\":\"verifies\",\"to\":\"lex.space\"}");
    try testing.expect(!get(linked, "isError").bool);
    try testing.expect(std.mem.find(u8, try s.tmp.dir.readFileAlloc(testing.io, "spec/lex.md", s.arena.allocator(), .limited(1 << 16)), "verifies=lex.token,lex.space") != null);

    // what is refused, and what is missing, is an error the agent reads
    const refused = try s.call("link", "{\"from\":\"c.one\",\"type\":\"verifies\",\"to\":\"no.such\"}");
    try testing.expect(get(refused, "isError").bool);
    try testing.expect(std.mem.find(u8, get(try content(&s, refused), "output").string, "there is no item 'no.such'") != null);
    try testing.expect(get(try s.call("trace", "{}"), "isError").bool);
}

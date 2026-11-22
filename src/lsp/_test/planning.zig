//! The requests of the planning views: the schedule, and what a drag in a
//! view writes into the item's file.

// req: lsp.planning
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

const task_type =
    \\statuses = ["open", "doing", "done"]
    \\[attributes.start]
    \\type = "date"
    \\[attributes.days]
    \\type = "integer"
    \\[attributes.mode]
    \\[planning]
    \\start = "start"
    \\duration = "days"
    \\mode = "mode"
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
        try write(dir, ".skein/config.toml", "[[sources]]\npath = \"plan\"\n\n[[sources]]\npath = \"tasks\"\nkind = \"items\"\ntype = \"task\"\n");
        try write(dir, ".skein/types/task.toml", task_type);
        try write(dir, ".skein/links/precedes.toml", "[planning]\nrole = \"precedes\"\n");
        try write(dir, ".skein/resources.toml", "[calendar]\n");
        try write(dir, "plan/plan.md", "%task[t.design start=2027-03-01 days=5 precedes=t.build] Design.\n\n%task[t.build days=3 doing] Build.\n");
        try write(dir, "tasks/t.docs.md", "+++\nid = \"t.docs\"\nstart = 2027-03-01\ndays = 2\n+++\n\nDocumentation.\n");
        self.root = try dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.server = .{ .gpa = testing.allocator, .io = testing.io, .out = &self.out.writer, .version = "test" };
        const a = self.arena.allocator();
        const root_uri = try uri_paths.fromPath(a, try Io.Dir.path.join(a, &.{ self.root, "" }), self.server.style);
        _ = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{\"rootUri\":\"{s}\"}}}}", .{root_uri});
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
        while (try jsonrpc.readMessage(a, &reader)) |body| {
            try messages.append(a, try json.parseFromSliceLeaky(json.Value, a, body, .{}));
        }
        return messages.items;
    }

    /// The answer to a request, the first message the server sends for it
    fn request(self: *Session, method: []const u8, params: []const u8) !json.Value {
        self.next_id += 1;
        const answer = try self.send("{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{s}}}", .{ self.next_id, method, params });
        for (answer) |m| if (m.object.get("id") != null) return m.object.get("result") orelse m.object.get("error").?;
        return error.TestUnexpectedResult;
    }

    fn read(self: *Session, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, path, self.arena.allocator(), .limited(1 << 20));
    }
};

fn get(v: json.Value, name: []const u8) json.Value {
    return v.object.get(name).?;
}

fn entry(result: json.Value, id: []const u8) !json.Value {
    for (get(result, "items").array.items) |e| if (std.mem.eql(u8, get(e, "id").string, id)) return e;
    return error.TestUnexpectedResult;
}

test "skein/schedule: the work items with their dates, links, statuses and the calendar" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    const result = try s.request("skein/schedule", "{}");
    const build = try entry(result, "t.build");
    try testing.expectEqualStrings("2027-03-08", get(build, "start").string);
    try testing.expectEqualStrings("2027-03-10", get(build, "finish").string);
    try testing.expectEqualStrings("float", get(build, "mode").string);
    try testing.expectEqualStrings("doing", get(build, "status").string);
    try testing.expectEqualStrings("t.design", get(build, "after").array.items[0].string);
    try testing.expect(get(build, "critical").bool);
    try testing.expectEqual(3, get(result, "statuses").array.items.len);
    try testing.expect(!get(result, "workdays").array.items[5].bool);
}

test "skein/plan: a bar moved or resized, and a card moved, are written into the files" {
    var s: Session = undefined;
    try s.init();
    defer s.deinit();
    // the float build, dragged to a later start: fixed there from then on
    _ = try s.request("skein/plan", "{\"id\":\"t.build\",\"start\":\"2027-03-10\"}");
    try testing.expectEqualStrings("%task[t.design start=2027-03-01 days=5 precedes=t.build] Design.\n\n%task[t.build days=3 doing start=2027-03-10 mode=fixed] Build.\n", try s.read("plan/plan.md"));
    // the design, made longer to end on Tuesday the 9th: seven working days
    _ = try s.request("skein/plan", "{\"id\":\"t.design\",\"finish\":\"2027-03-09\"}");
    try testing.expect(std.mem.find(u8, try s.read("plan/plan.md"), "%task[t.design start=2027-03-01 days=7 precedes=t.build]") != null);
    // a card moved to "done", in an item file
    _ = try s.request("skein/plan", "{\"id\":\"t.docs\",\"status\":\"done\"}");
    try testing.expectEqualStrings("+++\nid = \"t.docs\"\nstatus = \"done\"\nstart = 2027-03-01\ndays = 2\n+++\n\nDocumentation.\n", try s.read("tasks/t.docs.md"));
    // and the stored schedule follows
    try testing.expect(std.mem.find(u8, try s.read(".skein/schedule.toml"), "[items.\"t.build\"]\nstart = 2027-03-10\n") != null);
    // what cannot be is refused with the reason
    try testing.expectEqualStrings("skein: 'later' is not a status of a 'task'", get(try s.request("skein/plan", "{\"id\":\"t.docs\",\"status\":\"later\"}"), "message").string);
}

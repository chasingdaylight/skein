//! The Model Context Protocol server: JSON-RPC 2.0, one message a line,
//! with the tools of tools.zig.
//!
//! - `initialize`: the protocol version (the client's, when skein knows
//!   it), the tools capability, and what skein is
//! - `tools/list`, `tools/call`, `ping`
//! - notifications (`notifications/initialized` and others) are taken in
//!   silence

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;

const tools = @import("tools.zig");

const Server = @This();

pub const Error = Io.Writer.Error || Allocator.Error;

io: Io,
out: *Io.Writer,
version: []const u8,
/// the project's directory, as `--root` gives it
root: []const u8 = ".",

/// The versions of the protocol skein answers in, newest first
const versions = [_][]const u8{ "2025-06-18", "2025-03-26", "2024-11-05" };

const instructions =
    \\skein keeps requirements, specifications and their traceability as items in Markdown: a paragraph or list entry with a marker `%TYPE[ID words key=value]` is an item, `%[ID]` refers to one, and `key=ID` in a marker is a link. Use `items` to find items, `trace` to see one with everything linked to it, and run `check` after editing documents, item files or .skein/.
;

/// Answers one message (a line of JSON); `a` is freed after it
pub fn handle(s: *Server, a: Allocator, line: []const u8) Error!void {
    const msg = json.parseFromSliceLeaky(json.Value, a, line, .{}) catch return s.fail(a, .null, -32700, "parse error");
    if (msg != .object) return s.fail(a, .null, -32600, "not an object");
    const method = switch (msg.object.get("method") orelse return) {
        .string => |m| m,
        else => return s.fail(a, msg.object.get("id") orelse .null, -32600, "no method"),
    };
    // a notification is answered with nothing
    const id = msg.object.get("id") orelse return;
    const params = msg.object.get("params") orelse .null;
    if (std.mem.eql(u8, method, "initialize")) return s.initialize(a, id, params);
    if (std.mem.eql(u8, method, "ping")) return s.respond(a, id, .{});
    if (std.mem.eql(u8, method, "tools/list")) return s.list(a, id);
    if (std.mem.eql(u8, method, "tools/call")) return s.call(a, id, params);
    return s.fail(a, id, -32601, method);
}

fn initialize(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const asked = if (params == .object) params.object.get("protocolVersion") else null;
    var version: []const u8 = versions[0];
    if (asked) |v| if (v == .string) for (versions) |known| if (std.mem.eql(u8, known, v.string)) {
        version = known;
    };
    try s.respond(a, id, .{
        .protocolVersion = version,
        .capabilities = .{ .tools = .{ .listChanged = false } },
        .serverInfo = .{ .name = "skein", .version = s.version },
        .instructions = instructions,
    });
}

fn list(s: *Server, a: Allocator, id: json.Value) Error!void {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "{\"tools\":[");
    for (tools.all, 0..) |t, i| {
        if (i > 0) try out.append(a, ',');
        try out.print(a, "{{\"name\":{f},\"description\":{f},\"inputSchema\":{s}}}", .{ fmtJson(t.name), fmtJson(t.description), t.input_schema });
    }
    try out.appendSlice(a, "]}");
    try s.write(a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{s}}}", .{ fmtJson(id), out.items }));
}

fn call(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const name = if (params == .object) params.object.get("name") else null;
    if (name == null or name.? != .string) return s.fail(a, id, -32602, "tools/call: no name");
    const args = if (params == .object) params.object.get("arguments") orelse .null else .null;
    const answer = tools.call(s.io, a, s.root, name.?.string, args) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => tools.Answer{ .text = try a.print("{{\"error\":\"skein failed: {t}\"}}", .{e}), .is_error = true },
    };
    try s.respond(a, id, .{
        .content = &[_]struct { type: []const u8 = "text", text: []const u8 }{.{ .text = answer.text }},
        .isError = answer.is_error,
    });
}

fn respond(s: *Server, a: Allocator, id: json.Value, result: anytype) Error!void {
    try s.write(a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}", .{ fmtJson(id), fmtJson(result) }));
}

fn fail(s: *Server, a: Allocator, id: json.Value, code: i64, message: []const u8) Error!void {
    try s.write(a, try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{{\"code\":{d},\"message\":{f}}}}}", .{ fmtJson(id), code, fmtJson(message) }));
}

/// One message, on a line of its own
fn write(s: *Server, a: Allocator, body: []const u8) Error!void {
    _ = a;
    try s.out.writeAll(body);
    try s.out.writeByte('\n');
    try s.out.flush();
}

fn fmtJson(v: anytype) json.Formatter(@TypeOf(v)) {
    return json.fmt(v, .{ .emit_null_optional_fields = false });
}

test {
    _ = @import("_test/server.zig");
}

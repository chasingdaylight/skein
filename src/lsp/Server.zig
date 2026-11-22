//! The language server: its state and the messages it answers.
//!
//! - `initialize`, `initialized`, `shutdown`, `exit`
//! - the documents the editor has open (full text sync)
//! - diagnostics: the problems of `skein check`, published for every file
//!   when the server starts and whenever a file is opened or saved. The
//!   project is read from the files on disk, so a change shows when it is
//!   saved.
//! - `textDocument/definition`, `references` and `hover` on the ID of an
//!   item, wherever it is written
//!
//! The project is read again for each of these; nothing is kept between
//! messages but the text of the open documents.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Workspace = @import("../commands/Workspace.zig");
const check = @import("../commands/check.zig");
const jsonrpc = @import("jsonrpc.zig");
const protocol = @import("protocol.zig");
const query = @import("query.zig");
const uri_paths = @import("uri.zig");

const Server = @This();

pub const Error = Io.Writer.Error || Allocator.Error;

gpa: Allocator,
io: Io,
out: *Io.Writer,
version: []const u8,
style: uri_paths.Style = if (sysinfo.target.os.tag == .windows) .windows else .posix,
/// the directory the editor has open, owned by `gpa`
root: ?[]u8 = null,
/// the text of the open documents by URI (keys and values owned by `gpa`)
docs: std.StringHashMapUnmanaged([]u8) = .empty,
/// the files (paths from the project's root) with diagnostics published,
/// which a later check clears (keys owned by `gpa`)
published: std.StringHashMapUnmanaged(void) = .empty,
state: enum { uninitialized, running, shut_down } = .uninitialized,
/// false once `exit` has come
running: bool = true,

pub fn deinit(s: *Server) void {
    var docs = s.docs.iterator();
    while (docs.next()) |e| {
        s.gpa.free(e.key_ptr.*);
        s.gpa.free(e.value_ptr.*);
    }
    s.docs.deinit(s.gpa);
    var published = s.published.keyIterator();
    while (published.next()) |k| s.gpa.free(k.*);
    s.published.deinit(s.gpa);
    if (s.root) |r| s.gpa.free(r);
}

/// The exit code once the client has gone: 0 after `shutdown`
pub fn exitCode(s: *const Server) u8 {
    return if (s.state == .shut_down) 0 else 1;
}

/// Answers one message; `a` is freed after it
pub fn handle(s: *Server, a: Allocator, body: []const u8) Error!void {
    const msg = json.parseFromSliceLeaky(json.Value, a, body, .{}) catch {
        return s.respondError(a, .null, protocol.error_codes.parse_error, "parse error");
    };
    if (msg != .object) return s.respondError(a, .null, protocol.error_codes.invalid_request, "not an object");
    const id = msg.object.get("id");
    // a response to a request of the server's: nothing waits for it
    const method = switch (msg.object.get("method") orelse return) {
        .string => |m| m,
        else => return s.respondError(a, id orelse .null, protocol.error_codes.invalid_request, "no method"),
    };
    const params = msg.object.get("params") orelse .null;
    if (id) |i| return s.request(a, i, method, params);
    return s.notification(a, method, params);
}

fn request(s: *Server, a: Allocator, id: json.Value, method: []const u8, params: json.Value) Error!void {
    if (std.mem.eql(u8, method, "initialize")) return s.initialize(a, id, params);
    if (s.state == .uninitialized) return s.respondError(a, id, protocol.error_codes.server_not_initialized, "not initialized");
    if (std.mem.eql(u8, method, "shutdown")) {
        s.state = .shut_down;
        return s.respond(a, id, null);
    }
    if (std.mem.eql(u8, method, "textDocument/definition")) return s.definition(a, id, params);
    if (std.mem.eql(u8, method, "textDocument/references")) return s.references(a, id, params);
    if (std.mem.eql(u8, method, "textDocument/hover")) return s.hover(a, id, params);
    return s.respondError(a, id, protocol.error_codes.method_not_found, method);
}

fn notification(s: *Server, a: Allocator, method: []const u8, params: json.Value) Error!void {
    if (std.mem.eql(u8, method, "exit")) {
        s.running = false;
        return;
    }
    if (s.state != .running) return;
    if (std.mem.eql(u8, method, "initialized")) return s.publish(a);
    if (std.mem.eql(u8, method, "textDocument/didOpen")) {
        const p = parse(protocol.DidOpenParams, a, params) orelse return;
        try s.setText(p.textDocument.uri, p.textDocument.text);
        return s.publish(a);
    }
    if (std.mem.eql(u8, method, "textDocument/didChange")) {
        const p = parse(protocol.DidChangeParams, a, params) orelse return;
        if (p.contentChanges.len > 0) try s.setText(p.textDocument.uri, p.contentChanges[p.contentChanges.len - 1].text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didSave")) return s.publish(a);
    if (std.mem.eql(u8, method, "workspace/didChangeWatchedFiles")) return s.publish(a);
    if (std.mem.eql(u8, method, "textDocument/didClose")) {
        const p = parse(protocol.TextDocumentParams, a, params) orelse return;
        if (s.docs.fetchRemove(p.textDocument.uri)) |kv| {
            s.gpa.free(kv.key);
            s.gpa.free(kv.value);
        }
    }
}

fn initialize(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    if (s.state != .uninitialized) return s.respondError(a, id, protocol.error_codes.invalid_request, "initialized already");
    s.root = try s.rootOf(params);
    s.state = .running;
    try s.respond(a, id, protocol.InitializeResult{ .serverInfo = .{ .name = "skein", .version = s.version } });
}

/// The directory the editor has open: `rootUri`, else the first of
/// `workspaceFolders`, else `rootPath`; owned by `gpa`
fn rootOf(s: *Server, params: json.Value) Allocator.Error!?[]u8 {
    if (field(params, "rootUri") == .string) return uri_paths.toPath(s.gpa, field(params, "rootUri").string, s.style);
    const folders = field(params, "workspaceFolders");
    if (folders == .array and folders.array.items.len > 0) {
        const u = field(folders.array.items[0], "uri");
        if (u == .string) return uri_paths.toPath(s.gpa, u.string, s.style);
    }
    if (field(params, "rootPath") == .string) return try s.gpa.dupe(u8, field(params, "rootPath").string);
    return null;
}

fn setText(s: *Server, uri: []const u8, text: []const u8) Allocator.Error!void {
    const copy = try s.gpa.dupe(u8, text);
    errdefer s.gpa.free(copy);
    if (s.docs.getPtr(uri)) |old| {
        s.gpa.free(old.*);
        old.* = copy;
        return;
    }
    const key = try s.gpa.dupe(u8, uri);
    errdefer s.gpa.free(key);
    try s.docs.put(s.gpa, key, copy);
}

/// The project the editor has open, read from its files; null when the
/// editor has no directory open or there is no project in it
fn open(s: *Server, a: Allocator) ?Workspace {
    const root = s.root orelse return null;
    const opened = Workspace.open(s.io, a, .{ .root = root }) catch return null;
    return switch (opened) {
        .ok => |ws| ws,
        .failed => null,
    };
}

/// The URI of a file of the project
fn uriOf(s: *Server, a: Allocator, ws: *const Workspace, file: []const u8) Allocator.Error![]const u8 {
    const path = try Io.Dir.path.join(a, &.{ ws.root_path, file });
    return uri_paths.fromPath(a, path, s.style);
}

/// The path from the project's root, with forward slashes, of the file
/// `uri` names; null when it is not a file of the project
fn fileOf(s: *Server, a: Allocator, ws: *const Workspace, uri: []const u8) Allocator.Error!?[]const u8 {
    const path = try uri_paths.toPath(a, uri, s.style) orelse return null;
    const root = ws.root_path;
    if (path.len <= root.len + 1 or !uri_paths.samePath(s.style, path[0..root.len], root)) return null;
    if (path[root.len] != '/' and path[root.len] != '\\') return null;
    const file = try a.dupe(u8, path[root.len + 1 ..]);
    std.mem.replaceScalar(u8, file, '\\', '/');
    return file;
}

/// Checks the project and publishes its problems, file by file; a file
/// that had problems and has none now is told so
fn publish(s: *Server, a: Allocator) Error!void {
    var by_file: std.array_hash_map.String(std.ArrayList(protocol.Diagnostic)) = .empty;
    var ws_or_null = s.open(a);
    if (ws_or_null) |*ws| {
        defer ws.close();
        try check.all(s.io, a, ws);
        for (ws.report.problems.items) |p| {
            const entry = try by_file.getOrPut(a, p.file);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            const line: usize = if (p.line > 0) p.line - 1 else 0;
            const column: usize = if (p.column > 0) p.column - 1 else 0;
            try entry.value_ptr.append(a, .{
                // to the end of the line: an editor ends the range where the line does
                .range = .{ .start = .{ .line = line, .character = column }, .end = .{ .line = line, .character = 10_000 } },
                .message = p.message,
            });
        }
        // the files that had problems and have none now
        var old = s.published.keyIterator();
        while (old.next()) |file| {
            if (by_file.contains(file.*)) continue;
            try s.notify(a, "textDocument/publishDiagnostics", protocol.PublishDiagnosticsParams{ .uri = try s.uriOf(a, ws, file.*), .diagnostics = &.{} });
        }
        for (by_file.keys(), by_file.values()) |file, list| {
            try s.notify(a, "textDocument/publishDiagnostics", protocol.PublishDiagnosticsParams{ .uri = try s.uriOf(a, ws, file), .diagnostics = list.items });
        }
    }
    // remember which files have problems now
    var keys = s.published.keyIterator();
    while (keys.next()) |k| s.gpa.free(k.*);
    s.published.clearRetainingCapacity();
    for (by_file.keys()) |file| {
        const key = try s.gpa.dupe(u8, file);
        errdefer s.gpa.free(key);
        try s.published.put(s.gpa, key, {});
    }
}

/// The item the cursor is on, with the project it is in
const Found = struct { ws: Workspace, item: *const Item };

fn find(s: *Server, a: Allocator, params: json.Value) Allocator.Error!?Found {
    const p = parse(protocol.PositionParams, a, params) orelse return null;
    var ws = s.open(a) orelse return null;
    if (!ws.items_read) {
        ws.close();
        return null;
    }
    const file = try s.fileOf(a, &ws, p.textDocument.uri) orelse {
        ws.close();
        return null;
    };
    // what the editor shows, which may not be saved yet
    const text = s.docs.get(p.textDocument.uri) orelse ws.root.readFileAlloc(s.io, file, a, .limited(1 << 26)) catch {
        ws.close();
        return null;
    };
    const item = query.itemAt(&ws.graph, file, text, .{ .line = p.position.line, .character = p.position.character }) orelse {
        ws.close();
        return null;
    };
    return .{ .ws = ws, .item = item };
}

fn locationOf(s: *Server, a: Allocator, ws: *const Workspace, file: []const u8, line: u32, column: u32) Allocator.Error!protocol.Location {
    const l: usize = if (line > 0) line - 1 else 0;
    const c: usize = if (column > 0) column - 1 else 0;
    return .{ .uri = try s.uriOf(a, ws, file), .range = .{ .start = .{ .line = l, .character = c }, .end = .{ .line = l, .character = c } } };
}

fn definition(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    var found = try s.find(a, params) orelse return s.respond(a, id, null);
    defer found.ws.close();
    try s.respond(a, id, try s.locationOf(a, &found.ws, found.item.file, found.item.line, 1));
}

fn references(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    var found = try s.find(a, params) orelse return s.respond(a, id, null);
    defer found.ws.close();
    const ws = &found.ws;
    const target = found.item.id;
    const declared = (parse(protocol.PositionParams, a, params) orelse return s.respond(a, id, null)).context.includeDeclaration;

    var out: std.ArrayList(protocol.Location) = .empty;
    if (declared) try out.append(a, try s.locationOf(a, ws, found.item.file, found.item.line, 1));
    for (ws.graph.items) |*item| {
        for (item.links) |link| {
            if (std.mem.eql(u8, link.target, target)) try out.append(a, try s.locationOf(a, ws, item.file, if (link.line > 0) link.line else item.line, 1));
        }
        for (item.references) |r| {
            if (std.mem.eql(u8, r.target, target)) try out.append(a, try s.locationOf(a, ws, item.file, r.line, r.column));
        }
    }
    for (ws.graph.mentions) |m| {
        if (std.mem.eql(u8, m.target, target)) try out.append(a, try s.locationOf(a, ws, m.file, m.line, m.column));
    }
    for (ws.citations.all) |c| {
        if (std.mem.eql(u8, c.target, target)) try out.append(a, try s.locationOf(a, ws, c.file, c.line, c.column));
    }
    try s.respond(a, id, out.items);
}

fn hover(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    var found = try s.find(a, params) orelse return s.respond(a, id, null);
    defer found.ws.close();
    const item = found.item;
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "**{s}** ({s}", .{ item.id, item.type_name });
    if (item.category) |c| try text.print(a, ", {s}", .{c});
    if (found.ws.project.schema.itemType(item.type_name)) |t| try text.print(a, ", {s}", .{item.effectiveStatus(t)});
    try text.print(a, ")\n\n{s}", .{item.text});
    if (item.parts.len > 0) {
        try text.appendSlice(a, "\n\nParts:");
        for (item.parts) |part| try text.print(a, " `{s}`", .{part});
    }
    try s.respond(a, id, protocol.Hover{ .contents = .{ .value = text.items } });
}

fn notify(s: *Server, a: Allocator, method: []const u8, params: anytype) Error!void {
    const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"method\":{f},\"params\":{f}}}", .{ fmtJson(method), fmtJson(params) });
    try jsonrpc.writeMessage(s.out, body);
}

fn respond(s: *Server, a: Allocator, id: json.Value, result: anytype) Error!void {
    const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}", .{ fmtJson(id), fmtJson(result) });
    try jsonrpc.writeMessage(s.out, body);
}

fn respondError(s: *Server, a: Allocator, id: json.Value, code: i64, message: []const u8) Error!void {
    const e: protocol.ResponseError = .{ .code = code, .message = message };
    const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{f}}}", .{ fmtJson(id), fmtJson(e) });
    try jsonrpc.writeMessage(s.out, body);
}

/// The member `name` of `v`, null when there is none
fn field(v: json.Value, name: []const u8) json.Value {
    if (v != .object) return .null;
    return v.object.get(name) orelse .null;
}

fn fmtJson(v: anytype) json.Formatter(@TypeOf(v)) {
    return json.fmt(v, .{ .emit_null_optional_fields = false });
}

/// `params` as a `T`, or null when they do not fit
fn parse(comptime T: type, a: Allocator, params: json.Value) ?T {
    return json.parseFromValueLeaky(T, a, params, .{ .ignore_unknown_fields = true }) catch null;
}

test {
    _ = jsonrpc;
    _ = query;
    _ = uri_paths;
    _ = Graph;
    _ = @import("_test/server.zig");
}

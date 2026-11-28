//! The language server: its state and the messages it answers.
//!
//! - `initialize`, `initialized`, `shutdown`, `exit`
//! - the documents the editor has open (full text sync)
//! - diagnostics: the problems of `skein check`, published for every file
//!   when the server starts and whenever a file is opened or saved. The
//!   project is read from the files on disk, so a change shows when it is
//!   saved.
//! - `textDocument/definition`, `references` and `hover` on the ID of an
//!   item, wherever it is written; completion and rename
//! - code lenses above items (lens.zig) and quick fixes (fixes.zig)
//! - skein's own requests for the editor's views (views.zig) and its
//!   planning views (planning.zig)
//!
//! A request is about the project of the document it names, the nearest
//! `.skein/` above it, or the project it names (`project`, a URI of its
//! root); else the first project found in the editor's folders
//! (projects.zig). Diagnostics are published for every project found.
//! `skein/projects` lists them. The project is read again for each
//! message; nothing is kept between messages but the text of the open
//! documents and the roots of the projects.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Network = @import("../network/Network.zig");
const Report = @import("../Report.zig");
const Workspace = @import("../commands/Workspace.zig");
const check = @import("../commands/check.zig");
const complete = @import("complete.zig");
const fixes = @import("fixes.zig");
const form = @import("form.zig");
const lens = @import("lens.zig");
const move = @import("../commands/move.zig");
const network = @import("network.zig");
const planning = @import("planning.zig");
const discovery = @import("projects.zig");
const views = @import("views.zig");
const Schema = @import("../schema/Schema.zig");
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
/// the roots of the projects found in the editor's folders and of the
/// documents opened since, owned by `gpa`; the first is the one a request
/// that names none is about
projects: std.ArrayList([]u8) = .empty,
/// the directories the editor has open, owned by `gpa`
folders: std.ArrayList([]u8) = .empty,
/// the text of the open documents by URI (keys and values owned by `gpa`)
docs: std.StringHashMapUnmanaged([]u8) = .empty,
/// the URIs of the files with diagnostics published, which a later check
/// clears (keys owned by `gpa`)
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
    for (s.projects.items) |r| s.gpa.free(r);
    s.projects.deinit(s.gpa);
    for (s.folders.items) |f| s.gpa.free(f);
    s.folders.deinit(s.gpa);
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
    if (std.mem.eql(u8, method, "textDocument/completion")) return s.completion(a, id, params);
    if (std.mem.eql(u8, method, "textDocument/prepareRename")) return s.prepareRename(a, id, params);
    if (std.mem.eql(u8, method, "textDocument/rename")) return s.rename(a, id, params);
    if (std.mem.eql(u8, method, "textDocument/codeLens")) return lens.codeLens(s, a, id, params);
    if (std.mem.eql(u8, method, "textDocument/codeAction")) return fixes.codeAction(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/projects")) return s.listProjects(a, id);
    if (std.mem.eql(u8, method, "skein/items")) return views.items(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/itemAt")) return views.itemAt(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/trace")) return views.trace(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/coverage")) return views.coverage(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/render")) return views.render(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/graph")) return network.graph(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/form")) return form.form(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/saveItem")) return form.save(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/schedule")) return planning.scheduleOf(s, a, id, params);
    if (std.mem.eql(u8, method, "skein/plan")) return planning.plan(s, a, id, params);
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
        try s.adopt(a, p.textDocument.uri);
        return s.publish(a);
    }
    if (std.mem.eql(u8, method, "textDocument/didChange")) {
        const p = parse(protocol.DidChangeParams, a, params) orelse return;
        if (p.contentChanges.len > 0) try s.setText(p.textDocument.uri, p.contentChanges[p.contentChanges.len - 1].text);
        return;
    }
    if (std.mem.eql(u8, method, "textDocument/didSave")) return s.publish(a);
    if (std.mem.eql(u8, method, "workspace/didChangeWatchedFiles")) return s.publish(a);
    if (std.mem.eql(u8, method, "workspace/didChangeWorkspaceFolders")) {
        const event = field(params, "event");
        for (try s.folderPaths(a, field(event, "removed"))) |gone| {
            var i: usize = 0;
            while (i < s.folders.items.len) {
                if (uri_paths.samePath(s.style, s.folders.items[i], gone)) s.gpa.free(s.folders.orderedRemove(i)) else i += 1;
            }
        }
        try s.addFolders(try s.folderPaths(a, field(event, "added")));
        try s.findProjects(a);
        return s.publish(a);
    }
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
    try s.addFolders(try s.foldersOf(a, params));
    try s.findProjects(a);
    s.state = .running;
    try s.respond(a, id, protocol.InitializeResult{ .serverInfo = .{ .name = "skein", .version = s.version } });
}

/// The directories the editor has open: every one of `workspaceFolders`,
/// else `rootUri`, else `rootPath`
fn foldersOf(s: *Server, a: Allocator, params: json.Value) Allocator.Error![]const []const u8 {
    const folders = try s.folderPaths(a, field(params, "workspaceFolders"));
    if (folders.len > 0) return folders;
    if (field(params, "rootUri") == .string) {
        if (try uri_paths.toPath(a, field(params, "rootUri").string, s.style)) |path| return a.dupe([]const u8, &.{path});
    }
    if (field(params, "rootPath") == .string) return a.dupe([]const u8, &.{field(params, "rootPath").string});
    return &.{};
}

/// The paths of a list of workspace folders (`{ "uri": URI }`)
fn folderPaths(s: *Server, a: Allocator, list: json.Value) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    if (list != .array) return out.items;
    for (list.array.items) |f| {
        const u = field(f, "uri");
        if (u != .string) continue;
        if (try uri_paths.toPath(a, u.string, s.style)) |path| try out.append(a, path);
    }
    return out.items;
}

fn addFolders(s: *Server, paths: []const []const u8) Allocator.Error!void {
    for (paths) |path| {
        const copy = try s.gpa.dupe(u8, path);
        errdefer s.gpa.free(copy);
        try s.folders.append(s.gpa, copy);
    }
}

/// The projects again: those of the folders, then those of the open
/// documents
fn findProjects(s: *Server, a: Allocator) Allocator.Error!void {
    for (s.projects.items) |r| s.gpa.free(r);
    s.projects.clearRetainingCapacity();
    const folders: []const []const u8 = @ptrCast(s.folders.items);
    try discovery.discover(s.io, s.gpa, folders, &s.projects);
    var docs = s.docs.keyIterator();
    while (docs.next()) |uri| try s.adopt(a, uri.*);
}

/// Remembers the project of the document `uri`, when it is in one, so
/// that its problems are published
fn adopt(s: *Server, a: Allocator, uri: []const u8) Allocator.Error!void {
    const path = try uri_paths.toPath(a, uri, s.style) orelse return;
    const root = discovery.rootOf(s.io, a, path) orelse return;
    try discovery.add(s.gpa, &s.projects, root);
}

/// `skein/projects`: the name and root of each project
fn listProjects(s: *Server, a: Allocator, id: json.Value) Error!void {
    const Entry = struct { name: []const u8, uri: []const u8 };
    var out: std.ArrayList(Entry) = .empty;
    for (s.projects.items) |root| {
        var ws = s.openAt(a, root) orelse continue;
        defer ws.close();
        try out.append(a, .{ .name = ws.project.name, .uri = try uri_paths.fromPath(a, ws.root_path, s.style) });
    }
    try s.respond(a, id, out.items);
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

/// The project a request is about, read from its files: the one `params`
/// names (`project`, a URI of its root or of a place in it), else that of
/// the document it names (`textDocument.uri` or `uri`), else the first
/// project found; null when there is none
pub fn open(s: *Server, a: Allocator, params: json.Value) ?Workspace {
    const start = (s.startOf(a, params) catch return null) orelse return null;
    return s.openAt(a, start);
}

fn startOf(s: *Server, a: Allocator, params: json.Value) Allocator.Error!?[]const u8 {
    const named = field(params, "project");
    if (named == .string) return uri_paths.toPath(a, named.string, s.style);
    const doc = field(field(params, "textDocument"), "uri");
    const u = if (doc == .string) doc else field(params, "uri");
    if (u == .string) return uri_paths.toPath(a, u.string, s.style);
    if (s.projects.items.len > 0) return s.projects.items[0];
    return null;
}

/// The project at `start` or above it
fn openAt(s: *Server, a: Allocator, start: []const u8) ?Workspace {
    const opened = Workspace.open(s.io, a, .{ .root = start }) catch return null;
    return switch (opened) {
        .ok => |ws| ws,
        .failed => null,
    };
}

/// The URI of a file of the project
pub fn uriOf(s: *Server, a: Allocator, ws: *const Workspace, file: []const u8) Allocator.Error![]const u8 {
    const path = try Io.Dir.path.join(a, &.{ ws.root_path, file });
    return uri_paths.fromPath(a, path, s.style);
}

/// The path from the project's root, with forward slashes, of the file
/// `uri` names; null when it is not a file of the project
pub fn fileOf(s: *Server, a: Allocator, ws: *const Workspace, uri: []const u8) Allocator.Error!?[]const u8 {
    const path = try uri_paths.toPath(a, uri, s.style) orelse return null;
    const root = ws.root_path;
    if (path.len <= root.len + 1 or !uri_paths.samePath(s.style, path[0..root.len], root)) return null;
    if (path[root.len] != '/' and path[root.len] != '\\') return null;
    const file = try a.dupe(u8, path[root.len + 1 ..]);
    std.mem.replaceScalar(u8, file, '\\', '/');
    return file;
}

/// What the editor shows of `uri` (the file `file` of the project), which
/// may not be saved yet; null when it cannot be read
pub fn textOf(s: *Server, a: Allocator, ws: *const Workspace, uri: []const u8, file: []const u8) ?[]const u8 {
    return s.docs.get(uri) orelse ws.root.readFileAlloc(s.io, file, a, .limited(1 << 26)) catch null;
}

/// Publishes the problems again, after a change the server made
pub fn publishAll(s: *Server, a: Allocator) Error!void {
    return s.publish(a);
}

/// Checks every project and publishes its problems, file by file; a file
/// that had problems and has none now is told so
fn publish(s: *Server, a: Allocator) Error!void {
    var by_file: std.array_hash_map.String(std.ArrayList(protocol.Diagnostic)) = .empty;
    for (s.projects.items) |root| {
        var ws = s.openAt(a, root) orelse continue;
        defer ws.close();
        try check.all(s.io, a, &ws);
        // LSP severities: 1 an error, 2 a warning
        for ([_]struct { list: []const Report.Problem, severity: u8 }{
            .{ .list = ws.report.problems.items, .severity = 1 },
            .{ .list = ws.report.warnings.items, .severity = 2 },
        }) |kind| for (kind.list) |p| {
            const entry = try by_file.getOrPut(a, try s.uriOf(a, &ws, p.file));
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            const line: usize = if (p.line > 0) p.line - 1 else 0;
            const column: usize = if (p.column > 0) p.column - 1 else 0;
            try entry.value_ptr.append(a, .{
                // to the end of the line: an editor ends the range where the line does
                .range = .{ .start = .{ .line = line, .character = column }, .end = .{ .line = line, .character = 10_000 } },
                .severity = kind.severity,
                .message = p.message,
                .data = if (p.fix) |f| .{ .old = f.old, .new = f.new } else null,
            });
        };
    }
    // the files that had problems and have none now
    var old = s.published.keyIterator();
    while (old.next()) |uri| {
        if (by_file.contains(uri.*)) continue;
        try s.notify(a, "textDocument/publishDiagnostics", protocol.PublishDiagnosticsParams{ .uri = uri.*, .diagnostics = &.{} });
    }
    for (by_file.keys(), by_file.values()) |uri, list| {
        try s.notify(a, "textDocument/publishDiagnostics", protocol.PublishDiagnosticsParams{ .uri = uri, .diagnostics = list.items });
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
pub const Found = struct { ws: Workspace, item: *const Item };

pub fn find(s: *Server, a: Allocator, params: json.Value) Allocator.Error!?Found {
    const p = parse(protocol.PositionParams, a, params) orelse return null;
    var ws = s.open(a, params) orelse return null;
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

/// Where the item of another repository under the cursor (`name:id`) is
/// declared, in that repository's checkout; null when the word is no such
/// item, or its repository has no checkout on disk
fn otherDefinition(s: *Server, a: Allocator, params: json.Value) Allocator.Error!?protocol.Location {
    const p = parse(protocol.PositionParams, a, params) orelse return null;
    var ws = s.open(a, params) orelse return null;
    defer ws.close();
    const file = try s.fileOf(a, &ws, p.textDocument.uri) orelse return null;
    const text = s.docs.get(p.textDocument.uri) orelse ws.root.readFileAlloc(s.io, file, a, .limited(1 << 26)) catch return null;
    const line = query.lineOf(text, p.position.line) orelse return null;
    const word = query.wordAt(line, p.position.character) orelse return null;
    if (Network.split(word) == null) return null;
    const n = ws.graph.others orelse return null;
    const f = switch (n.resolve(word)) {
        .item => |f| f,
        else => return null,
    };
    const checkout = f.member.repository.path orelse return null;
    const path = try Io.Dir.path.resolveAlloc(a, &.{ ws.root_path, checkout, f.item.file });
    const l: usize = if (f.item.line > 0) f.item.line - 1 else 0;
    return .{ .uri = try uri_paths.fromPath(a, path, s.style), .range = .{ .start = .{ .line = l, .character = 0 }, .end = .{ .line = l, .character = 0 } } };
}

fn locationOf(s: *Server, a: Allocator, ws: *const Workspace, file: []const u8, line: u32, column: u32) Allocator.Error!protocol.Location {
    const l: usize = if (line > 0) line - 1 else 0;
    const c: usize = if (column > 0) column - 1 else 0;
    return .{ .uri = try s.uriOf(a, ws, file), .range = .{ .start = .{ .line = l, .character = c }, .end = .{ .line = l, .character = c } } };
}

fn definition(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    if (try s.otherDefinition(a, params)) |location| return s.respond(a, id, location);
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

/// What can be written where the cursor is: an item type, an ID, or a
/// word or value of a marker
fn completion(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const p = parse(protocol.PositionParams, a, params) orelse return s.respond(a, id, null);
    var ws = s.open(a, params) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respond(a, id, null);
    const file = try s.fileOf(a, &ws, p.textDocument.uri) orelse return s.respond(a, id, null);
    const text = s.docs.get(p.textDocument.uri) orelse ws.root.readFileAlloc(s.io, file, a, .limited(1 << 26)) catch return s.respond(a, id, null);
    const line = query.lineOf(text, p.position.line) orelse return s.respond(a, id, null);
    const before = line[0..@min(p.position.character, line.len)];

    var list: Completions = .{ .a = a, .line = p.position.line, .end = before.len };
    const schema = &ws.project.schema;
    switch (complete.context(before)) {
        .none => {
            // in code and tests: the IDs after a citation marker
            for (ws.project.citations) |set| {
                const word = complete.citation(before, set.marker) orelse continue;
                try list.ids(&ws, word, set.to);
                break;
            }
        },
        .item_type => |word| {
            for (schema.types) |t| try list.add(word, try a.print("{s}[", .{t.name}), t.name, 7, null);
        },
        .id => |word| try list.ids(&ws, word, &.{}),
        .word => |w| if (schema.itemType(w.type_name)) |t| {
            for (t.categories) |c| try list.add(w.at, c, c, 20, "category");
            for (t.statuses) |status| try list.add(w.at, status, status, 20, "status");
            for (t.attributes) |attr| try list.add(w.at, try a.print("{s}=", .{attr.name}), attr.name, 5, "attribute");
            for (schema.links) |link| {
                if (link.from.len > 0 and !Schema.names.contains(link.from, t.name)) continue;
                try list.add(w.at, try a.print("{s}=", .{link.name}), link.name, 5, "link");
            }
            if (t.verification.len > 0) try list.add(w.at, "verification=", "verification", 5, null);
        },
        .value => |v| if (schema.itemType(v.type_name)) |t| {
            if (schema.linkType(v.key)) |link| {
                try list.ids(&ws, v.at, link.to);
            } else if (std.mem.eql(u8, v.key, "status")) {
                for (t.statuses) |status| try list.add(v.at, status, status, 20, null);
            } else if (std.mem.eql(u8, v.key, "verification")) {
                for (t.verification) |method| try list.add(v.at, method, method, 20, null);
            } else if (t.attribute(v.key)) |attr| {
                for (attr.values) |value| try list.add(v.at, value, value, 20, null);
            }
        },
    }
    try s.respond(a, id, list.items.items);
}

/// The completions of one request: each replaces the word being written
const Completions = struct {
    a: Allocator,
    line: usize,
    /// where the cursor is in the line
    end: usize,
    items: std.ArrayList(protocol.CompletionItem) = .empty,

    fn add(self: *Completions, word: complete.Context.Word, text: []const u8, label: []const u8, kind: u8, detail: ?[]const u8) Allocator.Error!void {
        try self.items.append(self.a, .{
            .label = label,
            .kind = kind,
            .detail = detail,
            .textEdit = .{
                .range = .{ .start = .{ .line = self.line, .character = word.start }, .end = .{ .line = self.line, .character = self.end } },
                .newText = text,
            },
        });
    }

    /// The items that are not removed, of the types `of` when it names any
    fn ids(self: *Completions, ws: *const Workspace, word: complete.Context.Word, of: []const []const u8) Allocator.Error!void {
        for (ws.graph.items) |*item| {
            if (of.len > 0 and !Schema.names.contains(of, item.type_name)) continue;
            const item_type = ws.project.schema.itemType(item.type_name) orelse continue;
            if (item.isTombstone(item_type)) continue;
            const detail = if (item.category) |c| try self.a.print("{s}, {s}", .{ item.type_name, c }) else item.type_name;
            try self.add(word, item.id, item.id, 18, detail);
        }
    }
};

/// The ID under the cursor, with where it is in its line; null when the
/// cursor is on no ID of an item
fn idAt(s: *Server, a: Allocator, params: json.Value) Allocator.Error!?struct { id: []const u8, range: protocol.Range } {
    const p = parse(protocol.PositionParams, a, params) orelse return null;
    var found = try s.find(a, params) orelse return null;
    defer found.ws.close();
    const text = s.docs.get(p.textDocument.uri) orelse return .{ .id = try a.dupe(u8, found.item.id), .range = .{ .start = p.position, .end = p.position } };
    const line = query.lineOf(text, p.position.line) orelse return null;
    const word = query.wordAt(line, p.position.character) orelse return .{ .id = try a.dupe(u8, found.item.id), .range = .{ .start = p.position, .end = p.position } };
    const start = @intFromPtr(word.ptr) - @intFromPtr(line.ptr);
    return .{
        .id = try a.dupe(u8, found.item.id),
        .range = .{ .start = .{ .line = p.position.line, .character = start }, .end = .{ .line = p.position.line, .character = start + word.len } },
    };
}

fn prepareRename(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const at = try s.idAt(a, params) orelse return s.respond(a, id, null);
    try s.respond(a, id, protocol.PrepareRename{ .range = at.range, .placeholder = at.id });
}

/// Renames the item under the cursor everywhere, on disk, as `skein move`
/// does. The open documents must be saved first: the rename is made in
/// the files, and the editor shows them again from there.
fn rename(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const p = parse(protocol.RenameParams, a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "rename: no new name");
    var ws = s.open(a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    var docs = s.docs.iterator();
    while (docs.next()) |doc| {
        const file = try s.fileOf(a, &ws, doc.key_ptr.*) orelse continue;
        const on_disk = ws.root.readFileAlloc(s.io, file, a, .limited(1 << 26)) catch continue;
        if (!std.mem.eql(u8, on_disk, doc.value_ptr.*)) {
            return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: save {s} first: the rename is made in the files", .{file}));
        }
    }
    const at = try s.idAt(a, params) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the cursor is on no item");
    const outcome = move.run(s.io, a, .{ .common = .{ .root = ws.root_path }, .old = at.id, .new = p.newName }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: the rename failed ({t})", .{e})),
    };
    if (outcome.status != .ok) {
        return s.respondError(a, id, protocol.error_codes.invalid_params, std.mem.trimEnd(u8, outcome.text, "\n"));
    }
    try s.respond(a, id, protocol.WorkspaceEdit{});
    try s.publish(a);
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
    const body = try a.print("{{\"jsonrpc\":\"2.0\",\"method\":{f},\"params\":{f}}}", .{ fmtJson(method), fmtJson(params) });
    try jsonrpc.writeMessage(s.out, body);
}

pub fn respond(s: *Server, a: Allocator, id: json.Value, result: anytype) Error!void {
    const body = try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}", .{ fmtJson(id), fmtJson(result) });
    try jsonrpc.writeMessage(s.out, body);
}

pub fn respondError(s: *Server, a: Allocator, id: json.Value, code: i64, message: []const u8) Error!void {
    const e: protocol.ResponseError = .{ .code = code, .message = message };
    const body = try a.print("{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{f}}}", .{ fmtJson(id), fmtJson(e) });
    try jsonrpc.writeMessage(s.out, body);
}

/// The member `name` of `v`, null when there is none
pub fn field(v: json.Value, name: []const u8) json.Value {
    if (v != .object) return .null;
    return v.object.get(name) orelse .null;
}

fn fmtJson(v: anytype) json.Formatter(@TypeOf(v)) {
    return json.fmt(v, .{ .emit_null_optional_fields = false });
}

/// `params` as a `T`, or null when they do not fit
pub fn parse(comptime T: type, a: Allocator, params: json.Value) ?T {
    return json.parseFromValueLeaky(T, a, params, .{ .ignore_unknown_fields = true }) catch null;
}

test {
    _ = jsonrpc;
    _ = query;
    _ = uri_paths;
    _ = complete;
    _ = discovery;
    _ = Graph;
    _ = @import("_test/server.zig");
    _ = @import("_test/views.zig");
    _ = @import("_test/planning.zig");
    _ = @import("_test/form.zig");
}

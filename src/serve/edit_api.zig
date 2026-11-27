//! `skein serve`'s requests for editing, which its pages make (edit.js),
//! each under `/_skein/`, answered with JSON (`{"error": WHY}` when refused):
//!
//! - `GET page?file=F`: whether the page's file may be edited, the items in
//!   it, and the item types, for a new one
//! - `GET source?file=F`: the file's text, and a hash of it; `POST source`
//!   (`{file, text, hash}`): writes it, unless it changed since (the hash)
//! - `POST check` (`{file, text}`): what `skein check` finds with the file
//!   as given, not saved
//! - `GET form?id=ID` or `?type=TYPE`: an item's form (edit/form.zig)
//! - `POST preview` (a form's values): what `check` finds with them;
//!   `POST save` (the values, and the hash): writes them (edit/item_form.zig)

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Project = @import("../Project.zig");
const Site = @import("Site.zig");
const Workspace = @import("../commands/Workspace.zig");
const answer = @import("answer.zig");
const guard = @import("guard.zig");
const check = @import("../commands/check.zig");
const edit_form = @import("../edit/form.zig");
const files = @import("../files.zig");
const item_form = @import("../edit/item_form.zig");

pub const Method = guard.Method;

/// The answer to `method` of `path` (under the prefix, without it) with
/// `query` and `body`; the caller holds the site's mutex
pub fn handle(arena: Allocator, s: *Site, method: Method, path: []const u8, query: []const u8, body: []const u8) !answer.Answer {
    var opened = switch (try Workspace.open(s.io, arena, s.options.common)) {
        .ok => |w| w,
        .failed => |o| return refuse(arena, o.text),
    };
    defer opened.close();
    const ws = &opened;
    if (method == .get and eql(path, "page")) return pageInfo(arena, s, ws, try param(arena, query, "file") orelse "");
    if (method == .get and eql(path, "source")) return source(arena, s, ws, try param(arena, query, "file") orelse "");
    if (method == .get and eql(path, "form")) return formOf(arena, s, ws, try param(arena, query, "id"), try param(arena, query, "type"));
    if (method != .post) return refuse(arena, "skein serve: no such request");
    const value = json.parseFromSliceLeaky(json.Value, arena, body, .{}) catch return refuse(arena, "skein serve: the request is not JSON");
    if (eql(path, "source")) return writeSource(arena, s, ws, value);
    if (eql(path, "check")) {
        const file = string(value, "file");
        if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
        return problems(arena, s, file, string(value, "text"));
    }
    const p = json.parseFromValueLeaky(edit_form.Save, arena, value, .{ .ignore_unknown_fields = true }) catch return refuse(arena, "skein serve: a form's values, with its type");
    if (eql(path, "preview")) return preview(arena, s, ws, p);
    if (eql(path, "save")) return save(arena, s, ws, p, string(value, "hash"));
    return refuse(arena, "skein serve: no such request");
}

fn pageInfo(arena: Allocator, s: *Site, ws: *Workspace, file: []const u8) !answer.Answer {
    _ = s;
    const Info = struct { id: []const u8, inDocument: bool };
    var items: std.ArrayList(Info) = .empty;
    for (ws.graph.items) |*it| {
        if (eql(it.file, file) and it.parent == null) try items.append(arena, .{ .id = it.id, .inDocument = it.in_document });
    }
    var types: std.ArrayList([]const u8) = .empty;
    if (ws.items_read) for (ws.project.schema.types) |t| try types.append(arena, t.name);
    const editable = isSource(ws, file) and ws.project.readOnlySource(file) == null;
    return reply(arena, .{ .editable = editable, .items = items.items, .types = types.items });
}

fn source(arena: Allocator, s: *Site, ws: *Workspace, file: []const u8) !answer.Answer {
    if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
    const text = ws.root.readFileAlloc(s.io, file, arena, .limited(1 << 26)) catch return refuse(arena, try arena.print("skein serve: {s} cannot be read", .{file}));
    return reply(arena, .{ .text = text, .hash = &hashOf(text) });
}

fn writeSource(arena: Allocator, s: *Site, ws: *Workspace, value: json.Value) !answer.Answer {
    const file = string(value, "file");
    if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
    if (try changed(arena, s, ws, file, string(value, "hash"))) |why| return refuse(arena, why);
    ws.root.writeFile(s.io, .{ .sub_path = file, .data = string(value, "text") }) catch return refuse(arena, try arena.print("skein serve: {s} cannot be written", .{file}));
    return reply(arena, .{ .file = file });
}

fn formOf(arena: Allocator, s: *Site, ws: *Workspace, id: ?[]const u8, type_name: ?[]const u8) !answer.Answer {
    switch (try edit_form.build(s.io, arena, ws, id, type_name)) {
        .refused => |why| return refuse(arena, why),
        .ok => |f| {
            const item = if (id) |i| ws.graph.find(i) else null;
            const text = if (item) |it| ws.root.readFileAlloc(s.io, it.file, arena, .limited(1 << 26)) catch "" else "";
            return reply(arena, .{ .form = f, .hash = &hashOf(text) });
        },
    }
}

fn preview(arena: Allocator, s: *Site, ws: *Workspace, p: edit_form.Save) !answer.Answer {
    return switch (try item_form.preview(s.io, arena, ws, p)) {
        .refused => |why| reply(arena, .{ .problems = &[_]Shown{.{ .severity = "error", .message = why }} }),
        .new => reply(arena, .{ .problems = &[_]Shown{} }),
        .text => |t| problems(arena, s, t.file, t.text),
    };
}

fn save(arena: Allocator, s: *Site, ws: *Workspace, p: edit_form.Save, hash: []const u8) !answer.Answer {
    if (!p.new) {
        const item = ws.graph.find(p.id) orelse return refuse(arena, try arena.print("skein: there is no item '{s}'", .{p.id}));
        if (try writable(arena, s, ws, item.file)) |why| return refuse(arena, why);
        if (try changed(arena, s, ws, item.file, hash)) |why| return refuse(arena, why);
    }
    return switch (try item_form.write(s.io, arena, ws, p)) {
        .refused => |why| refuse(arena, why),
        .written => |w| reply(arena, .{ .id = w.id, .file = w.file }),
    };
}

const Shown = struct { severity: []const u8, line: u32 = 0, column: u32 = 0, message: []const u8 };

/// What `check` finds with `file` as `text`: its own problems, and how
/// many the other files have
fn problems(arena: Allocator, s: *Site, file: []const u8, text: []const u8) !answer.Answer {
    var common = s.options.common;
    common.unsaved = &.{.{ .file = file, .text = text }};
    var ws = switch (try Workspace.open(s.io, arena, common)) {
        .ok => |w| w,
        .failed => |o| return refuse(arena, o.text),
    };
    defer ws.close();
    try check.all(s.io, arena, &ws);
    var shown: std.ArrayList(Shown) = .empty;
    var elsewhere: usize = 0;
    for ([_]struct { []const @import("../Report.zig").Problem, []const u8 }{ .{ ws.report.problems.items, "error" }, .{ ws.report.warnings.items, "warning" } }) |kind| {
        for (kind[0]) |p| {
            if (!eql(p.file, file)) {
                elsewhere += 1;
                continue;
            }
            try shown.append(arena, .{ .severity = kind[1], .line = p.line, .column = p.column, .message = p.message });
        }
    }
    return reply(arena, .{ .problems = shown.items, .elsewhere = elsewhere });
}

/// Why `file` may not be edited; null when it may
fn writable(arena: Allocator, s: *Site, ws: *Workspace, file: []const u8) !?[]const u8 {
    _ = s;
    if (!isSource(ws, file)) return try arena.print("skein serve: {s} is not a file of the project's sources", .{file});
    if (ws.project.readOnlySource(file)) |src| return try arena.print("skein serve: {s} is in the read-only source '{s}'", .{ file, src.path });
    return null;
}

/// Whether `file` is a Markdown file of one of the project's sources
fn isSource(ws: *Workspace, file: []const u8) bool {
    if (file.len == 0 or file[0] == '/' or std.mem.find(u8, file, "..") != null or std.mem.findScalar(u8, file, '\\') != null) return false;
    for (ws.project.sources) |src| {
        const listed = files.list(ws.io, ws.arena, ws.root, src.path, &.{".md"}) catch continue;
        for (listed) |f| if (eql(f, file)) return true;
    }
    return false;
}

/// Why a save must not go ahead: `file` changed since it was read as `hash`
fn changed(arena: Allocator, s: *Site, ws: *Workspace, file: []const u8, hash: []const u8) !?[]const u8 {
    const now = ws.root.readFileAlloc(s.io, file, arena, .limited(1 << 26)) catch return null;
    if (eql(&hashOf(now), hash)) return null;
    return try arena.print("skein serve: {s} changed since this page read it (in an editor, or by a pull); nothing was saved. Copy your change, close this, and the page loads the file as it is now", .{file});
}

pub fn hashOf(text: []const u8) [16]u8 {
    var out: [16]u8 = undefined;
    _ = std.mem.print(&out, "{x:0>16}", .{std.hash.Wyhash.hash(0, text)}) catch unreachable;
    return out;
}

fn reply(arena: Allocator, value: anytype) !answer.Answer {
    return .{ .content_type = "application/json", .body = try arena.print("{f}", .{json.fmt(value, .{})}) };
}

fn refuse(arena: Allocator, why: []const u8) !answer.Answer {
    return reply(arena, .{ .@"error" = std.mem.trimEnd(u8, why, "\n") });
}

fn string(v: json.Value, key: []const u8) []const u8 {
    if (v != .object) return "";
    const x = v.object.get(key) orelse return "";
    return if (x == .string) x.string else "";
}

/// The value of `key` in a query (`a=1&b=2`), decoded
fn param(arena: Allocator, query: []const u8, key: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const at = std.mem.findScalar(u8, pair, '=') orelse continue;
        if (!eql(pair[0..at], key)) continue;
        const raw = try arena.dupe(u8, pair[at + 1 ..]);
        std.mem.replaceScalar(u8, raw, '+', ' ');
        return std.Uri.percentDecodeInPlace(raw);
    }
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test {
    _ = @import("_test/edit_api.zig");
}

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
//! - `POST change` (`{action, name}`): starts, opens, merges, proposes or
//!   abandons a change (serve/saving.zig)
//! - `POST approve` (`{id, as}`): approves an item as it is, as `skein
//!   approve` does, by the person signed in
//!
//! A save is refused where the project's way of saving says it cannot go
//! ahead (`needsChange` when a change must be started first), and what it
//! wrote is committed after (serve/saving.zig).

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Project = @import("../Project.zig");
const Context = @import("Context.zig");
const Site = @import("Site.zig");
const approve = @import("../commands/approve.zig");
const Workspace = @import("../commands/Workspace.zig");
const answer = @import("answer.zig");
const guard = @import("guard.zig");
const check = @import("../commands/check.zig");
const edit_form = @import("../edit/form.zig");
const files = @import("../files.zig");
const item_form = @import("../edit/item_form.zig");
const saving = @import("saving.zig");
const sign_in = @import("sign_in.zig");
const signatures = @import("../graph/signatures.zig");
const query = @import("query.zig");

pub const Method = guard.Method;

/// The answer to `method` of `path` (under the prefix, without it) with
/// `q`, its query, and `body`; the caller holds the server's lock
pub fn handle(arena: Allocator, c: *Context, method: Method, path: []const u8, q: []const u8, body: []const u8) !answer.Answer {
    // a change is started, merged or taken away from the checkout that serves
    if (method == .post and eql(path, "change")) return changeRequest(arena, c, body);
    const s = c.site;
    var opened = switch (try Workspace.open(s.io, arena, s.options.common)) {
        .ok => |w| w,
        .failed => |o| return refuse(arena, o.text),
    };
    defer opened.close();
    const ws = &opened;
    if (method == .get and eql(path, "page")) return pageInfo(arena, c, ws, try query.param(arena, q, "file") orelse "");
    if (method == .get and eql(path, "source")) return source(arena, s, ws, try query.param(arena, q, "file") orelse "");
    if (method == .get and eql(path, "form")) return formOf(arena, s, ws, try query.param(arena, q, "id"), try query.param(arena, q, "type"));
    if (method != .post) return refuse(arena, "skein serve: no such request");
    const value = json.parseFromSliceLeaky(json.Value, arena, body, .{}) catch return refuse(arena, "skein serve: the request is not JSON");
    if (eql(path, "source")) return writeSource(arena, c, ws, value);
    if (eql(path, "approve")) return approveItem(arena, c, ws, value);
    if (eql(path, "check")) {
        const file = string(value, "file");
        if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
        return problems(arena, s, file, string(value, "text"));
    }
    const p = json.parseFromValueLeaky(edit_form.Save, arena, value, .{ .ignore_unknown_fields = true }) catch return refuse(arena, "skein serve: a form's values, with its type");
    if (eql(path, "preview")) return preview(arena, s, ws, p);
    if (eql(path, "save")) return save(arena, c, ws, p, string(value, "hash"));
    return refuse(arena, "skein serve: no such request");
}

fn pageInfo(arena: Allocator, c: *Context, ws: *Workspace, file: []const u8) !answer.Answer {
    const Info = struct { id: []const u8, inDocument: bool };
    var items: std.ArrayList(Info) = .empty;
    for (ws.graph.items) |*it| {
        if (eql(it.file, file) and it.parent == null) try items.append(arena, .{ .id = it.id, .inDocument = it.in_document });
    }
    var types: std.ArrayList([]const u8) = .empty;
    if (ws.items_read) for (ws.project.schema.types) |t| try types.append(arena, t.name);
    const editable = isSource(ws, file) and ws.project.readOnlySource(file) == null;
    return reply(arena, .{ .editable = editable, .items = items.items, .types = types.items, .saving = try saving.state(arena, c, ws), .signIn = c.sign_in });
}

fn source(arena: Allocator, s: *Site, ws: *Workspace, file: []const u8) !answer.Answer {
    if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
    const text = ws.root.readFileAlloc(s.io, file, arena, .limited(1 << 26)) catch return refuse(arena, try arena.print("skein serve: {s} cannot be read", .{file}));
    return reply(arena, .{ .text = text, .hash = &hashOf(text) });
}

fn writeSource(arena: Allocator, c: *Context, ws: *Workspace, value: json.Value) !answer.Answer {
    const s = c.site;
    const file = string(value, "file");
    if (try writable(arena, s, ws, file)) |why| return refuse(arena, why);
    if (try changed(arena, s, ws, file, string(value, "hash"))) |why| return refuse(arena, why);
    const st = try saving.state(arena, c, ws);
    if (try saving.before(arena, st)) |r| return reply(arena, .{ .@"error" = r.message, .needsChange = r.needs_change });
    ws.root.writeFile(s.io, .{ .sub_path = file, .data = string(value, "text") }) catch return refuse(arena, try arena.print("skein serve: {s} cannot be written", .{file}));
    const failed = try saving.after(arena, c, st, &.{file}, try arena.print("Edit {s}", .{file}));
    return reply(arena, .{ .file = file, .warning = failed });
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

fn save(arena: Allocator, c: *Context, ws: *Workspace, p: edit_form.Save, hash: []const u8) !answer.Answer {
    const s = c.site;
    if (!p.new) {
        const item = ws.graph.find(p.id) orelse return refuse(arena, try arena.print("skein: there is no item '{s}'", .{p.id}));
        if (try writable(arena, s, ws, item.file)) |why| return refuse(arena, why);
        if (try changed(arena, s, ws, item.file, hash)) |why| return refuse(arena, why);
    }
    const st = try saving.state(arena, c, ws);
    if (try saving.before(arena, st)) |r| return reply(arena, .{ .@"error" = r.message, .needsChange = r.needs_change });
    return switch (try item_form.write(s.io, arena, ws, p)) {
        .refused => |why| refuse(arena, why),
        .written => |w| reply(arena, .{ .id = w.id, .file = w.file, .warning = try saving.after(arena, c, st, &.{w.file}, try arena.print("{s} {s}", .{ if (p.new) "New" else "Edit", w.id })) }),
    };
}

fn changeRequest(arena: Allocator, c: *Context, body: []const u8) !answer.Answer {
    const value = json.parseFromSliceLeaky(json.Value, arena, body, .{}) catch return refuse(arena, "skein serve: the request is not JSON");
    var opened = switch (try Workspace.open(c.main.io, arena, c.main.options.common)) {
        .ok => |w| w,
        .failed => |o| return refuse(arena, o.text),
    };
    defer opened.close();
    return switch (try saving.change(arena, c, &opened, value)) {
        .ok => |said| reply(arena, .{ .said = said }),
        .failed => |why| refuse(arena, why),
    };
}

/// `POST approve` (`{id, as}`): an approval of the item as it is, by the
/// person signed in (git's user on this computer alone), in the role `as`
/// where its type names roles, saved as an edit is
fn approveItem(arena: Allocator, c: *Context, ws: *Workspace, value: json.Value) !answer.Answer {
    const id = string(value, "id");
    const item = ws.graph.find(id) orelse return refuse(arena, try arena.print("skein: there is no item '{s}'", .{id}));
    const st = try saving.state(arena, c, ws);
    if (try saving.before(arena, st)) |r| return reply(arena, .{ .@"error" = r.message, .needsChange = r.needs_change });
    const role = string(value, "as");
    // an approval that must be signed, where the project asks for a sign-in again to give it
    var fresh = false;
    if (c.user) |u| {
        const now = std.Io.Clock.real.now(c.site.io).toSeconds();
        fresh = u.again and u.at_unix >= now - sign_in.fresh_seconds;
        const item_type = ws.project.schema.itemType(item.type_name);
        const needs = item_type != null and signatures.needed(item_type.?, if (role.len > 0) role else null);
        if (needs and ws.project.workflow.approve_sign_in == .again and !fresh) {
            return reply(arena, .{ .@"error" = "skein serve: this approval must be signed: sign in again to give it", .again = true });
        }
    }
    const out = try approve.run(c.site.io, arena, .{
        .common = .{ .root = c.site.options.common.root },
        .ids = &.{id},
        .by = if (c.user) |u| u.login else null,
        .as = if (role.len > 0) role else null,
        // the electronic signature: how the approver was signed in
        .signed_in = if (c.user) |u| .{ .provider = u.provider, .subject = u.subject, .at = u.at, .again = fresh } else null,
    });
    if (out.status != .ok) return refuse(arena, out.text);
    // a sign-in again is for one approval
    if (fresh) if (c.session) |token| c.people.usedAgain(token);
    const warning = try saving.after(arena, c, st, &.{".skein/approvals"}, try arena.print("Approve {s}", .{id}));
    return reply(arena, .{ .said = std.mem.trimEnd(u8, out.text, "\n"), .warning = warning });
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

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test {
    _ = @import("_test/edit_api.zig");
}

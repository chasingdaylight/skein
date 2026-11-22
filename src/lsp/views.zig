//! skein's own requests, for the editor's views:
//!
//! - `skein/items`: every item, with where it is declared, for the tree
//! - `skein/itemAt` (a position): the ID of the item under the cursor
//! - `skein/trace` (`{ "id": ID }`): the item's trace as HTML
//! - `skein/coverage` (`{ "profile": P }`, optional): the coverage page as
//!   HTML, with what is covered of what is expected
//!
//! In the HTML, an item is linked as `skein:item/ID` and a place in a
//! file as `skein:file/PATH#LINE`, which the view opens in the editor.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Item = @import("../graph/Item.zig");
const Report = @import("../Report.zig");
const Results = @import("../results/Results.zig");
const Server = @import("Server.zig");
const Workspace = @import("../commands/Workspace.zig");
const expectations = @import("../graph/coverage.zig");
const generated = @import("../render/generated.zig");
const html = @import("../html/blocks.zig");
const protocol = @import("protocol.zig");
const trace_page = @import("trace_page.zig");

/// The longest title of an item in the tree
const title_len = 80;

const ItemInfo = struct {
    id: []const u8,
    type: []const u8,
    category: ?[]const u8 = null,
    status: []const u8,
    uri: []const u8,
    /// from the project's root, with forward slashes
    file: []const u8,
    /// 0-based
    line: usize,
    parent: ?[]const u8 = null,
    title: []const u8,
    /// the source the file is in: its path, or empty for none
    source: []const u8,
    removed: bool,
};

pub fn items(s: *Server, a: Allocator, id: json.Value) Server.Error!void {
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respond(a, id, null);
    var out: std.ArrayList(ItemInfo) = .empty;
    for (ws.graph.items) |*item| {
        const t = ws.project.schema.itemType(item.type_name) orelse continue;
        try out.append(a, .{
            .id = item.id,
            .type = item.type_name,
            .category = item.category,
            .status = item.effectiveStatus(t),
            .uri = try s.uriOf(a, &ws, item.file),
            .file = item.file,
            .line = if (item.line > 0) item.line - 1 else 0,
            .parent = item.parent,
            .title = titleOf(item.text),
            .source = sourceOf(&ws, item.file),
            .removed = item.isTombstone(t),
        });
    }
    var sources: std.ArrayList([]const u8) = .empty;
    for (ws.project.sources) |src| try sources.append(a, src.path);
    try s.respond(a, id, .{ .project = ws.project.name, .sources = sources.items, .items = out.items });
}

/// The first line of an item's text, shortened
fn titleOf(text: []const u8) []const u8 {
    const first = std.mem.trim(u8, generated.firstParagraph(text), " \t");
    const line = first[0 .. std.mem.findScalar(u8, first, '\n') orelse first.len];
    if (line.len <= title_len) return line;
    // not inside a UTF-8 sequence
    var end: usize = title_len;
    while (end > 0 and line[end] & 0xc0 == 0x80) end -= 1;
    return line[0..end];
}

fn sourceOf(ws: *const Workspace, file: []const u8) []const u8 {
    for (ws.project.sources) |src| {
        if (std.mem.startsWith(u8, file, src.path) and (file.len == src.path.len or file[src.path.len] == '/')) return src.path;
    }
    return "";
}

pub fn itemAt(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    var found = try s.find(a, params) orelse return s.respond(a, id, null);
    defer found.ws.close();
    try s.respond(a, id, .{ .id = found.item.id });
}

pub fn trace(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const want = Server.field(params, "id");
    if (want != .string) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein/trace: no id");
    var ws = s.open(a) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    const item = ws.graph.find(want.string) orelse ws.graph.formerly(want.string) orelse
        return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: there is no item '{s}'", .{want.string}));
    const results = try loadResults(s, a, &ws);
    const md = try trace_page.markdown(s.io, a, &ws, item, &results);
    try s.respond(a, id, .{ .id = item.id, .html = try toHtml(a, md) });
}

pub fn coverage(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    var ws = s.open(a) orelse return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: no project");
    defer ws.close();
    if (!ws.items_read) return s.respondError(a, id, protocol.error_codes.invalid_params, "skein: the project has problems that stop it being read");
    const name = Server.field(params, "profile");
    const profile = if (name == .string) ws.project.schema.profile(name.string) orelse
        return s.respondError(a, id, protocol.error_codes.invalid_params, try a.print("skein: there is no profile '{s}'", .{name.string})) else null;
    const results = try loadResults(s, a, &ws);
    const index = try results.index(a, &ws.graph, &ws.citations);
    const links: Links = .{ .a = a };
    const ctx: generated.Context = .{
        .arena = a,
        .project = &ws.project,
        .graph = &ws.graph,
        .citations = &ws.citations,
        .href = Links.item,
        .fileHref = Links.file,
        .href_ctx = &links,
        .default_profile = profile,
        .results = .{ .results = &results, .index = &index },
    };
    const md = try generated.render(ctx, if (name == .string) try a.print("coverage profile={s}", .{name.string}) else "coverage");
    var covered: usize = 0;
    var total: usize = 0;
    for (try expectations.compute(a, &ws.project, &ws.graph, &ws.citations, profile)) |e| {
        covered += e.covered;
        total += e.total;
    }
    const page = try a.print("# Coverage of {s}\n\n{s}", .{ ws.project.name, md });
    try s.respond(a, id, .{ .html = try toHtml(a, page), .covered = covered, .total = total });
}

/// The project's test results; those that cannot be read are left out
fn loadResults(s: *Server, a: Allocator, ws: *Workspace) Allocator.Error!Results {
    var ignored: Report = .{ .arena = a };
    return Results.load(s.io, a, ws.root, &ws.project, &ws.graph, &.{}, &ignored);
}

/// Where the links of a generated page lead in the view
const Links = struct {
    a: Allocator,

    fn item(ctx: *const anyopaque, it: *const Item) generated.Error![]const u8 {
        const self: *const Links = @ptrCast(@alignCast(ctx));
        return self.a.print("skein:item/{s}", .{it.id});
    }
    fn file(ctx: *const anyopaque, f: []const u8) generated.Error![]const u8 {
        const self: *const Links = @ptrCast(@alignCast(ctx));
        return self.a.print("skein:file/{s}", .{f});
    }
};

pub fn toHtml(a: Allocator, md: []const u8) Allocator.Error![]const u8 {
    var doc: html.Document = .{ .arena = a };
    try doc.render(md);
    return doc.out.items;
}

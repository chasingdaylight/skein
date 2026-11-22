//! Code lenses: above each item declared in a file, its links, when it has
//! any, which open a pick of the items they lead to (`skein.pickLinked`),
//! and "Trace" (`skein.trace`). The commands are the extension's.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Item = @import("../graph/Item.zig");
const Server = @import("Server.zig");
const protocol = @import("protocol.zig");
const walk = @import("../graph/walk.zig");

/// The links shown in a lens's title, of each direction; the others are counted
const shown = 3;

pub fn codeLens(s: *Server, a: Allocator, id: json.Value, params: json.Value) Server.Error!void {
    const p = Server.parse(protocol.TextDocumentParams, a, params) orelse return s.respond(a, id, null);
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respond(a, id, null);
    const file = try s.fileOf(a, &ws, p.textDocument.uri) orelse return s.respond(a, id, null);
    var out: std.ArrayList(protocol.CodeLens) = .empty;
    for (ws.graph.items) |*item| {
        if (!std.mem.eql(u8, item.file, file)) continue;
        const line: usize = if (item.line > 0) item.line - 1 else 0;
        const range: protocol.Range = .{ .start = .{ .line = line, .character = 0 }, .end = .{ .line = line, .character = 0 } };
        const incoming = try walk.incoming(a, &ws.graph, item.id);
        if (item.links.len + incoming.len > 0) try out.append(a, .{ .range = range, .command = .{
            .title = try title(a, item, incoming),
            .command = "skein.pickLinked",
            .arguments = try linked(a, item, incoming),
        } });
        try out.append(a, .{ .range = range, .command = .{
            .title = "Trace",
            .command = "skein.trace",
            .arguments = try a.dupe(json.Value, &.{.{ .string = item.id }}),
        } });
    }
    try s.respond(a, id, out.items);
}

/// "verifies lex.a · refines from sys.b, sys.c +2"
fn title(a: Allocator, item: *const Item, incoming: []const walk.Incoming) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (item.links[0..@min(shown, item.links.len)], 0..) |link, i| {
        if (i > 0) try out.appendSlice(a, ", ");
        try out.print(a, "{s} {s}", .{ link.type_name, link.target });
    }
    if (item.links.len > shown) try out.print(a, " +{d}", .{item.links.len - shown});
    if (incoming.len == 0) return out.items;
    if (item.links.len > 0) try out.appendSlice(a, " \u{00b7} ");
    for (incoming[0..@min(shown, incoming.len)], 0..) |in, i| {
        if (i > 0) try out.appendSlice(a, ", ");
        try out.print(a, "{s} from {s}", .{ in.link.type_name, in.from.id });
    }
    if (incoming.len > shown) try out.print(a, " +{d}", .{incoming.len - shown});
    return out.items;
}

/// The arguments of `skein.pickLinked`: the item, and each item linked
/// with how (`{ "id": ..., "label": ... }`)
fn linked(a: Allocator, item: *const Item, incoming: []const walk.Incoming) Allocator.Error![]const json.Value {
    var entries: json.Array = .init(a);
    for (item.links) |link| try entries.append(try entry(a, link.target, try a.print("{s} {s}", .{ link.type_name, link.target })));
    for (incoming) |in| try entries.append(try entry(a, in.from.id, try a.print("{s} from {s}", .{ in.link.type_name, in.from.id })));
    return a.dupe(json.Value, &.{ .{ .string = item.id }, .{ .array = entries } });
}

fn entry(a: Allocator, id: []const u8, label: []const u8) Allocator.Error!json.Value {
    var o: json.ObjectMap = .empty;
    try o.put(a, "id", .{ .string = id });
    try o.put(a, "label", .{ .string = label });
    return .{ .object = o };
}

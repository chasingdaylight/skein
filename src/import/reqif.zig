//! The spec objects of a ReqIF file as rows for an import, as a CSV file
//! gives them (#241): `id`, `text`, `reqif` (the object's identifier, to
//! find it again), a column for each attribute by its long name, and one for
//! each relation type, with the IDs of the targets. The ID is the value of
//! an attribute `id` (as `skein export reqif` writes it), else of
//! `ReqIF.ForeignID` (as DOORS writes it), else the identifier. The text is
//! the XHTML attribute `text` or `ReqIF.Text`, else the first XHTML one, as
//! Markdown. Enumerations give their values' long names. Objects come in the
//! order of the specifications, then the rest.

const std = @import("std");

const Rows = @import("../commands/import_csv.zig").Rows;
const xml = @import("../xml.zig");
const xhtml = @import("xhtml.zig");

const Element = xml.Element;
const Map = std.StringArrayHashMapUnmanaged([]const u8);

pub fn rows(arena: std.mem.Allocator, text: []const u8, file: []const u8) std.mem.Allocator.Error!Rows {
    var diag: xml.Diagnostic = .{};
    const root = xml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidXml => return .{ .failed = try arena.print("{s}:{d}:{d}: {s}", .{ file, diag.line, diag.column, diag.message }) },
    };
    const content = if (root.is("REQ-IF")) blk: {
        const core = root.child("CORE-CONTENT") orelse break :blk null;
        break :blk core.child("REQ-IF-CONTENT");
    } else null;
    const c = content orelse return .{ .failed = try arena.print("{s}: not ReqIF: no REQ-IF with CORE-CONTENT and REQ-IF-CONTENT", .{file}) };

    // long names by identifier: enumeration values, attribute definitions,
    // relation types
    var names: Map = .empty;
    if (c.child("DATATYPES")) |dts| for (dts.content) |n| {
        const dt = if (n == .element) n.element else continue;
        const values = dt.child("SPECIFIED-VALUES") orelse continue;
        for (try values.children(arena, "ENUM-VALUE")) |v| try named(arena, &names, v);
    };
    var relation_types: std.ArrayList([]const u8) = .empty;
    if (c.child("SPEC-TYPES")) |types| for (types.content) |n| {
        const t = if (n == .element) n.element else continue;
        if (t.is("SPEC-RELATION-TYPE")) {
            try named(arena, &names, t);
            const name = t.attribute("LONG-NAME") orelse t.attribute("IDENTIFIER") orelse continue;
            if (!contains(relation_types.items, name)) try relation_types.append(arena, name);
        }
        const attrs = t.child("SPEC-ATTRIBUTES") orelse continue;
        for (attrs.content) |a| if (a == .element) try named(arena, &names, a.element);
    };

    // the objects, in the order of the specifications
    var by_identifier: std.StringArrayHashMapUnmanaged(*const Element) = .empty;
    if (c.child("SPEC-OBJECTS")) |objects| for (try objects.children(arena, "SPEC-OBJECT")) |o| {
        if (o.attribute("IDENTIFIER")) |id| try by_identifier.put(arena, id, o);
    };
    var order: std.ArrayList([]const u8) = .empty;
    if (c.child("SPECIFICATIONS")) |specs| for (try specs.children(arena, "SPECIFICATION")) |s| try walk(arena, s, &order);
    for (by_identifier.keys()) |id| if (!contains(order.items, id)) try order.append(arena, id);

    // each object's values by column
    var columns: std.ArrayList([]const u8) = .empty;
    try columns.appendSlice(arena, &.{ "id", "text", "reqif" });
    var records: std.ArrayList(Map) = .empty;
    var ids: Map = .empty;
    for (order.items) |identifier| {
        const o = by_identifier.get(identifier) orelse continue;
        var r: Map = .empty;
        var text_value: ?[]const u8 = null;
        var first_xhtml: ?[]const u8 = null;
        if (o.child("VALUES")) |values| for (values.content) |n| {
            const v = if (n == .element) n.element else continue;
            const def = definition(v) orelse continue;
            const name = names.get(def) orelse def;
            const value = try valueOf(arena, v, &names) orelse continue;
            if (v.is("ATTRIBUTE-VALUE-XHTML")) {
                if (std.ascii.eqlIgnoreCase(name, "text") or std.ascii.eqlIgnoreCase(name, "ReqIF.Text")) {
                    text_value = value;
                    continue;
                }
                if (first_xhtml == null) first_xhtml = value;
            }
            const column = columnName(name);
            try r.put(arena, column, value);
            if (!contains(columns.items, column)) try columns.append(arena, column);
        };
        const id = r.get("id") orelse r.get("reqif-foreign-id") orelse identifier;
        _ = r.orderedRemove("id");
        try r.put(arena, "id", id);
        try r.put(arena, "text", text_value orelse first_xhtml orelse "");
        try r.put(arena, "reqif", identifier);
        try ids.put(arena, identifier, id);
        try records.append(arena, r);
    }

    // relations, as columns of their source
    if (c.child("SPEC-RELATIONS")) |relations| for (try relations.children(arena, "SPEC-RELATION")) |rel| {
        const source = ref(rel, "SOURCE") orelse continue;
        const target = ref(rel, "TARGET") orelse continue;
        const type_ref = ref(rel, "TYPE") orelse continue;
        const i = ids.getIndex(source) orelse continue;
        const target_id = ids.get(target) orelse continue;
        const column = columnName(names.get(type_ref) orelse type_ref);
        if (!contains(columns.items, column)) try columns.append(arena, column);
        const r = &records.items[i];
        const before = r.get(column);
        try r.put(arena, column, if (before) |b| try arena.print("{s},{s}", .{ b, target_id }) else target_id);
    };

    var out: std.ArrayList([]const []const u8) = .empty;
    try out.append(arena, columns.items);
    for (records.items) |r| {
        const row = try arena.alloc([]const u8, columns.items.len);
        for (columns.items, row) |col, *cell| cell.* = r.get(col) orelse "";
        try out.append(arena, row);
    }
    return .{ .rows = out.items };
}

fn named(arena: std.mem.Allocator, names: *Map, e: *const Element) !void {
    const id = e.attribute("IDENTIFIER") orelse return;
    try names.put(arena, id, e.attribute("LONG-NAME") orelse id);
}

/// The objects a specification holds, depth first
fn walk(arena: std.mem.Allocator, e: *const Element, order: *std.ArrayList([]const u8)) !void {
    const children = e.child("CHILDREN") orelse return;
    for (try children.children(arena, "SPEC-HIERARCHY")) |h| {
        if (ref(h, "OBJECT")) |id| if (!contains(order.items, id)) try order.append(arena, id);
        try walk(arena, h, order);
    }
}

/// The text of the reference element inside the child `name` of `e`
fn ref(e: *const Element, name: []const u8) ?[]const u8 {
    const c = e.child(name) orelse return null;
    for (c.content) |n| if (n == .element) {
        const t = n.element.content;
        if (t.len == 1 and t[0] == .text) return std.mem.trim(u8, t[0].text, " \t\r\n");
    };
    return null;
}

fn definition(v: *const Element) ?[]const u8 {
    return ref(v, "DEFINITION");
}

fn valueOf(arena: std.mem.Allocator, v: *const Element, names: *const Map) !?[]const u8 {
    if (v.is("ATTRIBUTE-VALUE-XHTML")) {
        const the = v.child("THE-VALUE") orelse return null;
        return try xhtml.markdown(arena, the);
    }
    if (v.is("ATTRIBUTE-VALUE-ENUMERATION")) {
        const values = v.child("VALUES") orelse return null;
        var out: std.ArrayList(u8) = .empty;
        for (values.content) |n| if (n == .element) {
            const t = n.element.content;
            if (t.len != 1 or t[0] != .text) continue;
            const id = std.mem.trim(u8, t[0].text, " \t\r\n");
            if (out.items.len > 0) try out.appendSlice(arena, ", ");
            try out.appendSlice(arena, names.get(id) orelse id);
        };
        return out.items;
    }
    return v.attribute("THE-VALUE");
}

/// A column for an attribute: `id`, `type` and `text` are Skein's own, so
/// an attribute so named that is not the one Skein takes gets `reqif-`
fn columnName(name: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(name, "id")) return "id";
    if (std.ascii.eqlIgnoreCase(name, "ReqIF.ForeignID")) return "reqif-foreign-id";
    // the standard name of an object's title, as Jama Connect writes it
    if (std.ascii.eqlIgnoreCase(name, "ReqIF.Name")) return "title";
    if (std.ascii.eqlIgnoreCase(name, "type")) return "reqif-type";
    if (std.ascii.eqlIgnoreCase(name, "text")) return "reqif-text";
    if (std.ascii.eqlIgnoreCase(name, "reqif")) return "reqif-reqif";
    return name;
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

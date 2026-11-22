//! A generated matrix with columns of one's choosing:
//!
//!     matrix complies-with columns=text,classes from.columns=status,approach,evidence
//!
//! `columns` are of the item pointed to, `from.columns` of the items that
//! point to it, one row for each of those; a column is `id`, `type`,
//! `category`, `status`, `text` (the first paragraph) or an attribute.
//! A value that is an item's ID is a link to it.

const std = @import("std");

const Item = @import("../graph/Item.zig");
const LinkType = @import("../schema/LinkType.zig");
const coverage = @import("../graph/coverage.zig");
const generated = @import("generated.zig");
const walk = @import("../graph/walk.zig");

const Error = generated.Error;

pub const Request = struct {
    ctx: generated.Context,
    link_type: *const LinkType,
    columns: []const []const u8,
    from_columns: []const []const u8,
};

pub fn render(req: Request, filter: *const generated.Filter) Error![]const u8 {
    const ctx = req.ctx;
    const a = ctx.arena;
    const schema = &ctx.project.schema;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "| Item |");
    for (req.columns) |c| try out.print(a, " {s} |", .{try heading(a, c)});
    try out.print(a, " `{s}` from |", .{req.link_type.name});
    for (req.from_columns) |c| try out.print(a, " {s} |", .{try heading(a, c)});
    try out.appendSlice(a, "\n|");
    for (0..2 + req.columns.len + req.from_columns.len) |_| try out.appendSlice(a, " --- |");
    try out.append(a, '\n');

    var rows: usize = 0;
    var covered: usize = 0;
    var waived: usize = 0;
    for (ctx.graph.items) |*item| {
        if (!filter.passes(schema, ctx.graph, item)) continue;
        rows += 1;
        var from: std.ArrayList(*const Item) = .empty;
        for (try walk.incoming(a, ctx.graph, item.id)) |in| {
            const as = if (schema.linkType(in.link.type_name)) |t| t.counts_as else null;
            if (std.mem.eql(u8, in.link.type_name, req.link_type.name) or (as != null and std.mem.eql(u8, as.?, req.link_type.name))) try from.append(a, in.from);
        }
        const excused = if (from.items.len == 0) coverage.excusedBy(schema, ctx.graph, item.id, req.link_type.name) else null;
        if (from.items.len > 0) covered += 1 else if (excused != null) waived += 1;
        // one row for each item pointing to it, when their columns are asked for
        const per_row = req.from_columns.len > 0 and from.items.len > 1;
        const lines: usize = if (per_row) from.items.len else 1;
        for (0..lines) |n| {
            try out.appendSlice(a, "| ");
            try generated.link(ctx, &out, item);
            try out.appendSlice(a, " |");
            for (req.columns) |c| {
                try out.append(a, ' ');
                try value(ctx, &out, item, c);
                try out.appendSlice(a, " |");
            }
            try out.append(a, ' ');
            const these = if (per_row) from.items[n .. n + 1] else from.items;
            if (these.len == 0) {
                if (excused) |by| {
                    try out.appendSlice(a, "waived by ");
                    try generated.link(ctx, &out, by);
                } else try out.appendSlice(a, "**none**");
            }
            for (these, 0..) |f, i| {
                if (i > 0) try out.appendSlice(a, ", ");
                try generated.link(ctx, &out, f);
            }
            try out.appendSlice(a, " |");
            for (req.from_columns) |c| {
                try out.append(a, ' ');
                if (these.len == 1) try value(ctx, &out, these[0], c);
                try out.appendSlice(a, " |");
            }
            try out.append(a, '\n');
        }
    }
    if (rows == 0) return a.print("*No item is selected.*\n", .{});
    try out.print(a, "\n{d} of {d} with a `{s}` link", .{ covered, rows - waived, req.link_type.name });
    try out.appendSlice(a, if (waived > 0) try a.print(", {d} waived.\n", .{waived}) else ".\n");
    return out.items;
}

/// A column's heading: `text` as Text, an attribute as itself
fn heading(a: std.mem.Allocator, column: []const u8) Error![]const u8 {
    if (column.len == 0) return column;
    const out = try a.dupe(u8, column);
    out[0] = std.ascii.toUpper(out[0]);
    return out;
}

/// The cell of `column` for `item`; a value that is an item's ID links to it
fn value(ctx: generated.Context, out: *std.ArrayList(u8), item: *const Item, column: []const u8) Error!void {
    const a = ctx.arena;
    const item_type = ctx.project.schema.itemType(item.type_name);
    if (std.mem.eql(u8, column, "id")) return generated.cell(a, out, item.id);
    if (std.mem.eql(u8, column, "type")) return generated.cell(a, out, item.type_name);
    if (std.mem.eql(u8, column, "category")) return generated.cell(a, out, item.category orelse "");
    if (std.mem.eql(u8, column, "status")) return generated.cell(a, out, if (item_type) |t| item.effectiveStatus(t) else item.status orelse "");
    if (std.mem.eql(u8, column, "text")) return generated.cell(a, out, generated.firstParagraph(item.text));
    for (item.attributes) |attr| {
        if (!std.mem.eql(u8, attr.name, column)) continue;
        const each: []const []const u8 = if (attr.values.len > 0) attr.values else &.{attr.value};
        for (each, 0..) |v, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            if (ctx.graph.find(v)) |target| try generated.link(ctx, out, target) else try generated.cell(a, out, v);
        }
        return;
    }
}

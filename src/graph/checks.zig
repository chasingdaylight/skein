//! What `skein check` holds every item to: its type's rules for IDs,
//! categories, statuses and attributes, and the schema's rules for links.

const std = @import("std");

const Graph = @import("Graph.zig");
const Item = @import("Item.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const datetime = @import("../toml/datetime.zig");

const Error = std.mem.Allocator.Error;

const Context = struct {
    graph: *const Graph,
    schema: *const Schema,
    report: *Report,

    /// Reports a problem with `item`, at `line` (0: where it is declared)
    fn problem(self: Context, item: *const Item, line: u32, comptime fmt: []const u8, args: anytype) Error!void {
        var buf: [512]u8 = undefined;
        const message = std.mem.print(&buf, fmt, args) catch "(a message too long to show)";
        try self.report.add(item.file, if (line > 0) line else item.line, 1, "{s}: {s}", .{ item.id, message });
    }
};

/// Reports everything wrong with the items of `graph`.
pub fn run(graph: *const Graph, schema: *const Schema, report: *Report) Error!void {
    const ctx: Context = .{ .graph = graph, .schema = schema, .report = report };
    for (graph.items) |*item| {
        const item_type = schema.itemType(item.type_name) orelse {
            try ctx.problem(item, 0, "there is no item type '{s}'", .{item.type_name});
            continue;
        };
        try checkOwn(ctx, item, item_type);
        try checkAttributes(ctx, item, item_type);
        try checkLinks(ctx, item, item_type);
        try checkReferences(ctx, item);
    }
    try checkMentions(ctx);
}

/// References in narrative text are held to what those in items are
fn checkMentions(ctx: Context) Error!void {
    for (ctx.graph.mentions) |m| {
        if (std.mem.findScalar(u8, m.target, ':') != null) continue;
        const target = ctx.graph.find(m.target) orelse {
            try ctx.report.add(m.file, m.line, m.column, "the text refers to '{s}', and there is no such item", .{m.target});
            continue;
        };
        const target_type = ctx.schema.itemType(target.type_name) orelse continue;
        if (target.isTombstone(target_type)) {
            try ctx.report.add(m.file, m.line, m.column, "the text refers to '{s}', which is removed", .{m.target});
        }
    }
}

/// The ID, the category, the status and the verification method
fn checkOwn(ctx: Context, item: *const Item, item_type: *const Schema.ItemType) Error!void {
    if (!item_type.idMatches(item.id)) switch (item_type.id) {
        .hierarchical => try ctx.problem(item, 0, "the ID of a '{s}' is lowercase words joined by dots, like 'lex.comment.line'", .{item_type.name}),
        .numbered => |n| try ctx.problem(item, 0, "the ID of a '{s}' is '{s}{s}' and {d} or more digits", .{ item_type.name, n.prefix, n.separator, n.digits }),
    };
    if (item.category) |c| {
        if (item_type.categories.len == 0) {
            try ctx.problem(item, 0, "a '{s}' has no categories, so '{s}' is none", .{ item_type.name, c });
        } else if (!Schema.names.contains(item_type.categories, c)) {
            try ctx.problem(item, 0, "'{s}' is not a category of a '{s}'", .{ c, item_type.name });
        }
    } else if (item_type.categories.len > 0 and !item.isTombstone(item_type)) {
        try ctx.problem(item, 0, "a '{s}' needs a category", .{item_type.name});
    }
    if (item.status) |s| {
        if (!Schema.names.contains(item_type.statuses, s)) try ctx.problem(item, 0, "'{s}' is not a status of a '{s}'", .{ s, item_type.name });
    }
    if (item.verification) |v| {
        if (!Schema.names.contains(item_type.verification, v)) try ctx.problem(item, 0, "'{s}' is not a verification method of a '{s}'", .{ v, item_type.name });
    }
}

fn checkAttributes(ctx: Context, item: *const Item, item_type: *const Schema.ItemType) Error!void {
    for (item.attributes) |a| {
        const declared = item_type.attribute(a.name) orelse {
            try ctx.problem(item, a.line, "'{s}' is not an attribute of a '{s}', nor a link type", .{ a.name, item_type.name });
            continue;
        };
        const fits = switch (declared.kind) {
            .string => declared.values.len == 0 or Schema.names.contains(declared.values, a.value),
            .integer => if (std.fmt.parseInt(i64, a.value, 10)) |_| true else |_| false,
            .boolean => std.mem.eql(u8, a.value, "true") or std.mem.eql(u8, a.value, "false"),
            .date => a.value.len == 10 and datetime.parse(a.value) != null,
        };
        if (!fits) switch (declared.kind) {
            .string => try ctx.problem(item, a.line, "'{s}' is not a value of '{s}'", .{ a.value, a.name }),
            .integer => try ctx.problem(item, a.line, "'{s}' must be an integer", .{a.name}),
            .boolean => try ctx.problem(item, a.line, "'{s}' must be true or false", .{a.name}),
            .date => try ctx.problem(item, a.line, "'{s}' must be a date, like 2027-03-01", .{a.name}),
        };
    }
    if (item.isTombstone(item_type)) return;
    for (item_type.attributes) |declared| {
        if (declared.required and item.attribute(declared.name) == null) try ctx.problem(item, 0, "a '{s}' needs the attribute '{s}'", .{ item_type.name, declared.name });
    }
}

fn checkLinks(ctx: Context, item: *const Item, item_type: *const Schema.ItemType) Error!void {
    for (item.links) |link| {
        const link_type = ctx.schema.linkType(link.type_name).?;
        if (link_type.from.len > 0 and !Schema.names.contains(link_type.from, item.type_name)) {
            try ctx.problem(item, link.line, "a '{s}' cannot have a '{s}' link", .{ item.type_name, link.type_name });
        }
        // an item of another repository; checked once repositories are linked
        if (std.mem.findScalar(u8, link.target, ':') != null) continue;
        const target = ctx.graph.find(link.target) orelse {
            try ctx.problem(item, link.line, "{s}: there is no item '{s}'", .{ link.type_name, link.target });
            continue;
        };
        if (std.mem.eql(u8, target.id, item.id)) try ctx.problem(item, link.line, "{s}: an item cannot link to itself", .{link.type_name});
        if (link_type.to.len > 0 and !Schema.names.contains(link_type.to, target.type_name)) {
            try ctx.problem(item, link.line, "{s}: '{s}' is a '{s}', which this link cannot point to", .{ link.type_name, target.id, target.type_name });
        }
        if (ctx.schema.itemType(target.type_name)) |target_type| {
            if (target.isTombstone(target_type) and !item.isTombstone(item_type)) {
                try ctx.problem(item, link.line, "{s}: '{s}' is removed", .{ link.type_name, target.id });
            }
        }
    }
    if (item.isTombstone(item_type)) return;
    for (ctx.schema.links) |link_type| {
        if (!link_type.required) continue;
        if (link_type.from.len > 0 and !Schema.names.contains(link_type.from, item.type_name)) continue;
        const has = for (item.links) |link| {
            if (std.mem.eql(u8, link.type_name, link_type.name)) break true;
        } else false;
        if (!has) try ctx.problem(item, 0, "a '{s}' needs a '{s}' link", .{ item.type_name, link_type.name });
    }
}

fn checkReferences(ctx: Context, item: *const Item) Error!void {
    for (item.references) |r| {
        if (std.mem.findScalar(u8, r.target, ':') != null) continue;
        const target = ctx.graph.find(r.target) orelse {
            try ctx.report.add(item.file, r.line, r.column, "{s}: the text refers to '{s}', and there is no such item", .{ item.id, r.target });
            continue;
        };
        const target_type = ctx.schema.itemType(target.type_name) orelse continue;
        if (target.isTombstone(target_type)) {
            try ctx.report.add(item.file, r.line, r.column, "{s}: the text refers to '{s}', which is removed", .{ item.id, r.target });
        }
    }
}

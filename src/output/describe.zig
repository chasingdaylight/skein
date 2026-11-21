//! An item with what the project knows about it, as JSON and as text.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Json = @import("Json.zig");
const Project = @import("../Project.zig");
const fingerprint = @import("../graph/fingerprint.zig");
const walk = @import("../graph/walk.zig");

pub const Error = std.mem.Allocator.Error;

/// What describing an item draws on
pub const Context = struct {
    arena: std.mem.Allocator,
    project: *const Project,
    graph: *const Graph,
    citations: *const Graph.Citations,
    reviews: *const Graph.Reviews,
    approvals: *const Graph.Approvals,
};

/// What a reviewed link is, in words; null for a link that is not reviewed
fn stateName(ctx: Context, item: *const Item, link: Item.Link) Error!?[]const u8 {
    const state = try ctx.reviews.stateOf(ctx.arena, &ctx.project.schema, ctx.graph, item, link) orelse return null;
    return switch (state) {
        .reviewed => "reviewed",
        .never_reviewed => "never reviewed",
        .suspect => "suspect",
    };
}

/// The item as a JSON object. `with_text` leaves the text out when false.
pub fn json(ctx: Context, j: *Json, item: *const Item, with_text: bool) Error!void {
    const item_type = ctx.project.schema.itemType(item.type_name);
    try j.beginObject();
    try j.key("id");
    try j.string(item.id);
    try j.key("type");
    try j.string(item.type_name);
    try j.key("category");
    try j.optional(item.category);
    try j.key("status");
    try j.optional(if (item_type) |t| item.effectiveStatus(t) else item.status);
    try j.key("removed");
    try j.boolean(if (item_type) |t| item.isTombstone(t) else false);
    try j.key("verification");
    try j.optional(item.verification);
    try j.key("file");
    try j.string(item.file);
    try j.key("line");
    try j.integer(item.line);
    try j.key("fingerprint");
    try j.string(&try fingerprint.of(ctx.arena, ctx.graph, &ctx.project.schema, item));

    try j.key("part_of");
    try j.optional(item.parent);
    try j.key("parts");
    try j.strings(item.parts);

    try j.key("attributes");
    try j.beginObject();
    for (item.attributes) |a| {
        try j.key(a.name);
        try j.string(a.value);
    }
    try j.endObject();

    try j.key("links");
    try j.beginArray();
    for (item.links) |link| {
        try j.beginObject();
        try j.key("type");
        try j.string(link.type_name);
        try j.key("target");
        try j.string(link.target);
        try j.key("review");
        try j.optional(try stateName(ctx, item, link));
        try j.endObject();
    }
    try j.endArray();

    try j.key("linked_from");
    try j.beginArray();
    for (try walk.incoming(ctx.arena, ctx.graph, item.id)) |in| {
        try j.beginObject();
        try j.key("type");
        try j.string(in.link.type_name);
        try j.key("from");
        try j.string(in.from.id);
        try j.key("review");
        try j.optional(try stateName(ctx, in.from, in.link));
        try j.endObject();
    }
    try j.endArray();

    try j.key("references");
    try j.strings(try referenceTargets(ctx.arena, item));
    try j.key("referenced_from");
    try j.strings(try walk.referencedBy(ctx.arena, ctx.graph, item.id));
    try j.key("mentioned_in");
    try j.beginArray();
    for (try walk.mentionsOf(ctx.arena, ctx.graph, item.id)) |m| {
        try j.beginObject();
        try j.key("file");
        try j.string(m.file);
        try j.key("line");
        try j.integer(m.line);
        try j.endObject();
    }
    try j.endArray();

    try j.key("approvals");
    try j.beginArray();
    for (try ctx.approvals.of(ctx.arena, item.id)) |approval| {
        try j.beginObject();
        try j.key("by");
        try j.string(approval.by);
        try j.key("on");
        try j.string(try ctx.arena.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ approval.on.year, approval.on.month, approval.on.day }));
        try j.key("current");
        try j.boolean(try Graph.Approvals.isCurrent(ctx.arena, ctx.graph, &ctx.project.schema, approval, item));
        try j.endObject();
    }
    try j.endArray();

    try j.key("citations");
    try j.beginArray();
    for (try ctx.citations.of(ctx.arena, item.id)) |c| {
        try j.beginObject();
        try j.key("set");
        try j.string(c.set);
        try j.key("file");
        try j.string(c.file);
        try j.key("line");
        try j.integer(c.line);
        try j.endObject();
    }
    try j.endArray();

    if (with_text) {
        try j.key("text");
        try j.string(item.text);
    }
    try j.endObject();
}

/// The IDs the item's text refers to, each once, in order
fn referenceTargets(arena: std.mem.Allocator, item: *const Item) Error![]const []const u8 {
    var seen: std.array_hash_map.String(void) = .empty;
    for (item.references) |r| try seen.put(arena, r.target, {});
    return seen.keys();
}

/// The item as text for a terminal: what it is, then each kind of thing
/// around it that there is any of.
pub fn text(ctx: Context, out: *std.ArrayList(u8), item: *const Item) Error!void {
    const a = ctx.arena;
    const item_type = ctx.project.schema.itemType(item.type_name);

    try out.print(a, "{s}  ({s}", .{ item.id, item.type_name });
    if (item.category) |c| try out.print(a, ", {s}", .{c});
    if (item_type) |t| try out.print(a, ", {s}", .{item.effectiveStatus(t)});
    try out.print(a, ")\n  {s}:{d}\n", .{ item.file, item.line });
    try out.print(a, "  fingerprint {s}\n", .{&try fingerprint.of(a, ctx.graph, &ctx.project.schema, item)});
    if (item.verification) |v| try out.print(a, "  verification = {s}\n", .{v});
    for (item.attributes) |attr| try out.print(a, "  {s} = {s}\n", .{ attr.name, attr.value });

    if (item.parent) |whole| try out.print(a, "\nPart of: {s}\n", .{whole});
    try list(a, out, "\nParts: ", item.parts);

    if (item.links.len > 0) try out.appendSlice(a, "\nLinks to:\n");
    for (item.links) |link| {
        try out.print(a, "  {s} {s}", .{ link.type_name, link.target });
        try typeNote(ctx, out, link.target);
        if (try stateName(ctx, item, link)) |state| try out.print(a, "  [{s}]", .{state});
        try out.append(a, '\n');
    }

    const incoming = try walk.incoming(a, ctx.graph, item.id);
    if (incoming.len > 0) try out.appendSlice(a, "\nLinked from:\n");
    for (incoming) |in| {
        try out.print(a, "  {s} {s} ({s})", .{ in.link.type_name, in.from.id, in.from.type_name });
        if (try stateName(ctx, in.from, in.link)) |state| try out.print(a, "  [{s}]", .{state});
        try out.append(a, '\n');
    }

    try list(a, out, "\nRefers to: ", try referenceTargets(a, item));
    try list(a, out, "\nReferred to by: ", try walk.referencedBy(a, ctx.graph, item.id));

    const mentions = try walk.mentionsOf(a, ctx.graph, item.id);
    if (mentions.len > 0) try out.appendSlice(a, "\nMentioned in:\n");
    for (mentions) |m| try out.print(a, "  {s}:{d}\n", .{ m.file, m.line });

    const approvals = try ctx.approvals.of(a, item.id);
    if (approvals.len > 0) try out.appendSlice(a, "\nApproved by:\n");
    for (approvals) |approval| {
        try out.print(a, "  {s} on {d:0>4}-{d:0>2}-{d:0>2}", .{ approval.by, approval.on.year, approval.on.month, approval.on.day });
        const current = try Graph.Approvals.isCurrent(a, ctx.graph, &ctx.project.schema, approval, item);
        if (!current) try out.appendSlice(a, "  [of an earlier version]");
        try out.append(a, '\n');
    }

    const cited = try ctx.citations.of(a, item.id);
    if (cited.len > 0) try out.appendSlice(a, "\nCited by:\n");
    for (cited) |c| try out.print(a, "  {s}  {s}:{d}\n", .{ c.set, c.file, c.line });

    try list(a, out, "\nAbove (all it rests on): ", try walk.reach(a, ctx.graph, item.id, .above));
    try list(a, out, "\nBelow (all that rests on it): ", try walk.reach(a, ctx.graph, item.id, .below));
}

/// " (type)" of the item `id`, or a note that there is none
fn typeNote(ctx: Context, out: *std.ArrayList(u8), id: []const u8) Error!void {
    if (ctx.graph.find(id)) |target| {
        try out.print(ctx.arena, " ({s})", .{target.type_name});
    } else if (std.mem.findScalar(u8, id, ':') == null) try out.appendSlice(ctx.arena, " (no such item)");
}

/// `label` and the IDs, on one line; nothing when there are none
fn list(arena: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, ids: []const []const u8) Error!void {
    if (ids.len == 0) return;
    try out.appendSlice(arena, label);
    for (ids, 0..) |id, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        try out.appendSlice(arena, id);
    }
    try out.append(arena, '\n');
}

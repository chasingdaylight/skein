//! The trace of an item as a page, in Markdown, for the editor's trace
//! view: what `skein trace` prints, with each item and place a link the
//! view opens (`skein:item/ID`, `skein:file/PATH#LINE`).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Report = @import("../Report.zig");
const Results = @import("../results/Results.zig");
const Workspace = @import("../commands/Workspace.zig");
const describe = @import("../output/describe.zig");
const generated = @import("../render/generated.zig");
const walk = @import("../graph/walk.zig");

pub fn markdown(io: Io, a: Allocator, ws: *Workspace, item: *const Item, results: *const Results) Allocator.Error![]const u8 {
    var ignored: Report = .{ .arena = a };
    const reviews = try Graph.Reviews.load(io, a, ws.root, &ignored);
    const approvals = try Graph.Approvals.load(io, a, ws.root, &ignored);
    const ctx: describe.Context = .{
        .arena = a,
        .project = &ws.project,
        .graph = &ws.graph,
        .citations = &ws.citations,
        .reviews = &reviews,
        .approvals = &approvals,
    };
    var p: Page = .{ .a = a, .graph = &ws.graph };
    const out = &p.out;

    try out.print(a, "# {s}\n\n", .{item.id});
    try out.print(a, "{s}", .{item.type_name});
    if (item.category) |c| try out.print(a, ", {s}", .{c});
    if (ws.project.schema.itemType(item.type_name)) |t| try out.print(a, ", {s}", .{item.effectiveStatus(t)});
    try out.appendSlice(a, " \u{00b7} ");
    try p.place(item.file, item.line);
    try out.appendSlice(a, "\n\n");
    if (item.text.len > 0) {
        var lines = std.mem.splitScalar(u8, std.mem.trim(u8, item.text, "\r\n"), '\n');
        while (lines.next()) |line| try out.print(a, "> {s}\n", .{std.mem.trimEnd(u8, line, "\r")});
        try out.append(a, '\n');
    }
    if (item.verification != null or item.attributes.len > 0) {
        try out.appendSlice(a, "| Attribute | Value |\n| --- | --- |\n");
        if (item.verification) |v| try out.print(a, "| verification | {s} |\n", .{v});
        for (item.attributes) |attr| {
            try out.print(a, "| {s} | ", .{attr.name});
            try generated.cell(a, out, attr.value);
            try out.appendSlice(a, " |\n");
        }
        try out.append(a, '\n');
    }

    if (item.parent) |whole| try p.ids("Part of", &.{whole});
    try p.ids("Parts", item.parts);
    if (item.aliases.len > 0) try out.print(a, "**Former IDs:** {s}\n\n", .{try std.mem.join(a, ", ", item.aliases)});

    if (item.links.len > 0) {
        try out.appendSlice(a, "## Links to\n\n| Link | Item | Review |\n| --- | --- | --- |\n");
        for (item.links) |link| {
            try out.print(a, "| {s} | ", .{link.type_name});
            try p.id(link.target);
            try out.print(a, " | {s} |\n", .{try describe.stateName(ctx, item, link) orelse ""});
        }
        try out.append(a, '\n');
    }
    const incoming = try walk.incoming(a, &ws.graph, item.id);
    if (incoming.len > 0) {
        try out.appendSlice(a, "## Linked from\n\n| Link | Item | Review |\n| --- | --- | --- |\n");
        for (incoming) |in| {
            try out.print(a, "| {s} | ", .{in.link.type_name});
            try p.id(in.from.id);
            try out.print(a, " | {s} |\n", .{try describe.stateName(ctx, in.from, in.link) orelse ""});
        }
        try out.append(a, '\n');
    }
    try p.ids("Refers to", try describe.referenceTargets(a, item));
    try p.ids("Referred to by", try walk.referencedBy(a, &ws.graph, item.id));

    const mentions = try walk.mentionsOf(a, &ws.graph, item.id);
    if (mentions.len > 0) {
        try out.appendSlice(a, "**Mentioned in:** ");
        for (mentions, 0..) |m, i| {
            if (i > 0) try out.appendSlice(a, ", ");
            try p.place(m.file, m.line);
        }
        try out.appendSlice(a, "\n\n");
    }
    const cited = try ws.citations.of(a, item.id);
    if (cited.len > 0) {
        try out.appendSlice(a, "## Cited by\n\n");
        for (cited) |c| {
            try out.print(a, "- {s}: ", .{c.set});
            try p.place(c.file, c.line);
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    const approved = try approvals.of(a, item.id);
    if (approved.len > 0) {
        try out.appendSlice(a, "## Approved by\n\n");
        for (approved) |approval| {
            try out.print(a, "- {s} on {d:0>4}-{d:0>2}-{d:0>2}", .{ approval.by, approval.on.year, approval.on.month, approval.on.day });
            if (approval.as) |role| try out.print(a, " as {s}", .{role});
            if (!try Graph.Approvals.isCurrent(a, &ws.graph, &ws.project.schema, approval, item)) try out.appendSlice(a, " (of an earlier version)");
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    try resultsOf(&p, results, item, &ws.graph, &ws.citations);

    try p.ids("Above (all it rests on)", try walk.reach(a, &ws.graph, item.id, .above));
    try p.ids("Below (all that rests on it)", try walk.reach(a, &ws.graph, item.id, .below));
    return out.items;
}

fn resultsOf(p: *Page, r: *const Results, item: *const Item, graph: *const Graph, citations: *const Graph.Citations) Allocator.Error!void {
    const a = p.a;
    const idx = try r.index(a, graph, citations);
    const mine: []const usize = if (idx.by_item.get(item.id)) |l| l.items else &.{};
    if (mine.len == 0) return;
    try p.out.appendSlice(a, "## Results\n\n| Implementation | Verdict | Test | Result |\n| --- | --- | --- | --- |\n");
    for (try r.implementations(a)) |implementation| {
        const name = try r.implementationName(a, implementation);
        const verdict = @tagName(r.verdict(&idx, item.id, implementation));
        for (mine) |i| {
            const one = r.all[i];
            if (!std.mem.eql(u8, one.implementation, implementation)) continue;
            try p.out.print(a, "| {s} | {s} | ", .{ name, verdict });
            try generated.cell(a, &p.out, one.label());
            try p.out.print(a, " | {s} |\n", .{@tagName(one.outcome)});
        }
    }
    try p.out.append(a, '\n');
}

const Page = struct {
    a: Allocator,
    graph: *const Graph,
    out: std.ArrayList(u8) = .empty,

    /// An ID, linked when it is an item of the project
    fn id(self: *Page, target: []const u8) Allocator.Error!void {
        if (self.graph.find(target) != null) {
            try self.out.print(self.a, "[`{s}`](skein:item/{s})", .{ target, target });
        } else try self.out.print(self.a, "`{s}`", .{target});
    }

    /// `label` and the IDs, as a paragraph; nothing when there are none
    fn ids(self: *Page, label: []const u8, list: []const []const u8) Allocator.Error!void {
        if (list.len == 0) return;
        try self.out.print(self.a, "**{s}:** ", .{label});
        for (list, 0..) |target, i| {
            if (i > 0) try self.out.appendSlice(self.a, ", ");
            try self.id(target);
        }
        try self.out.appendSlice(self.a, "\n\n");
    }

    fn place(self: *Page, file: []const u8, line: u32) Allocator.Error!void {
        try self.out.print(self.a, "[{s}:{d}](skein:file/{s}#{d})", .{ file, line, file, line });
    }
};

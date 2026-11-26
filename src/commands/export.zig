//! `skein export`: the project's graph for other tools. `json` (the
//! default) is everything; `items`, `links` and `citations` are lists as
//! CSV, for a spreadsheet.

const std = @import("std");
const Io = std.Io;

const Approvals = @import("../graph/Approvals.zig");
const cli = @import("../cli.zig");
const Csv = @import("../output/Csv.zig");
const Graph = @import("../graph/Graph.zig");
const Json = @import("../output/Json.zig");
const Reviews = @import("../graph/Reviews.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const coverage = @import("../graph/coverage.zig");
const describe = @import("../output/describe.zig");
const fingerprint = @import("../graph/fingerprint.zig");
const gitlab_requirements = @import("../forge/gitlab_requirements.zig");

pub const What = cli.Export.What;

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Export) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const profile = if (options.profile) |name| ws.project.schema.profile(name) orelse return .{
        .text = try arena.print("skein: there is no profile '{s}'\n", .{name}),
        .status = .misuse,
    } else null;
    var ignored: @import("../Report.zig") = .{ .arena = arena };
    const reviews = try Reviews.load(io, arena, ws.root, &ignored);
    const approvals = try Approvals.load(io, arena, ws.root, &ignored);
    const ctx: describe.Context = .{
        .arena = arena,
        .project = &ws.project,
        .graph = &ws.graph,
        .citations = &ws.citations,
        .reviews = &reviews,
        .approvals = &approvals,
    };
    const exporter: Exporter = .{ .ctx = ctx, .profile = profile };
    return .{ .text = switch (options.what) {
        .json => try exporter.json(),
        .items => try exporter.items(),
        .links => try exporter.links(),
        .citations => try exporter.citations(),
        .@"gitlab-requirements" => try exporter.gitlabRequirements(),
    } };
}

const Exporter = struct {
    ctx: describe.Context,
    profile: ?*const Schema.Profile,

    /// Whether the item `id` is among what is exported
    fn included(self: Exporter, item: *const Graph.Item) bool {
        const p = self.profile orelse return true;
        const item_type = self.ctx.project.schema.itemType(item.type_name) orelse return false;
        return coverage.inProfile(p, item, item_type);
    }

    fn json(self: Exporter) ![]const u8 {
        const project = self.ctx.project;
        var j: Json = .{ .arena = self.ctx.arena };
        try j.beginObject();
        try j.key("project");
        try j.string(project.name);
        try j.key("profile");
        try j.optional(if (self.profile) |p| p.name else null);

        try j.key("types");
        try j.beginArray();
        for (project.schema.types) |t| {
            try j.beginObject();
            try j.key("name");
            try j.string(t.name);
            try j.key("description");
            try j.string(t.description);
            try j.key("categories");
            try j.strings(t.categories);
            try j.key("statuses");
            try j.strings(t.statuses);
            try j.endObject();
        }
        try j.endArray();

        try j.key("link_types");
        try j.beginArray();
        for (project.schema.links) |l| {
            try j.beginObject();
            try j.key("name");
            try j.string(l.name);
            try j.key("description");
            try j.string(l.description);
            try j.key("from");
            try j.strings(l.from);
            try j.key("to");
            try j.strings(l.to);
            try j.key("required");
            try j.boolean(l.required);
            try j.key("expected");
            try j.boolean(l.expected);
            try j.key("review");
            try j.boolean(l.review);
            try j.endObject();
        }
        try j.endArray();

        try j.key("items");
        try j.beginArray();
        for (self.ctx.graph.items) |*item| {
            if (self.included(item)) try describe.json(self.ctx, &j, item, true);
        }
        try j.endArray();
        try j.endObject();
        return j.finish();
    }

    /// The items, not removed ones, as GitLab's requirements import takes them
    fn gitlabRequirements(self: Exporter) ![]const u8 {
        var list: std.ArrayList(*const Graph.Item) = .empty;
        for (self.ctx.graph.items) |*item| {
            const item_type = self.ctx.project.schema.itemType(item.type_name) orelse continue;
            if (self.included(item) and !item.isTombstone(item_type)) try list.append(self.ctx.arena, item);
        }
        return gitlab_requirements.importCsv(self.ctx.arena, list.items);
    }

    /// One row per item: what it is, its attributes (one column each,
    /// for every attribute any type declares), and its text
    fn items(self: Exporter) ![]const u8 {
        const a = self.ctx.arena;
        var attributes: std.ArrayList([]const u8) = .empty;
        for (self.ctx.project.schema.types) |t| {
            for (t.attributes) |attr| {
                if (!Schema.names.contains(attributes.items, attr.name)) try attributes.append(a, attr.name);
            }
        }
        var csv: Csv = .{ .arena = a };
        for ([_][]const u8{ "id", "type", "category", "status", "verification", "part_of", "file", "line", "fingerprint" }) |h| try csv.field(h);
        for (attributes.items) |name| try csv.field(name);
        try csv.field("text");
        try csv.endRow();

        for (self.ctx.graph.items) |*item| {
            if (!self.included(item)) continue;
            const item_type = self.ctx.project.schema.itemType(item.type_name);
            try csv.field(item.id);
            try csv.field(item.type_name);
            try csv.field(item.category orelse "");
            try csv.field(if (item_type) |t| item.effectiveStatus(t) else item.status orelse "");
            try csv.field(item.verification orelse "");
            try csv.field(item.parent orelse "");
            try csv.field(item.file);
            try csv.integer(item.line);
            try csv.field(&try fingerprint.of(a, self.ctx.graph, &self.ctx.project.schema, item));
            for (attributes.items) |name| try csv.field(item.attribute(name) orelse "");
            try csv.field(item.text);
            try csv.endRow();
        }
        return csv.out.items;
    }

    /// One row per link: a traceability matrix in its long form
    fn links(self: Exporter) ![]const u8 {
        const a = self.ctx.arena;
        var csv: Csv = .{ .arena = a };
        try csv.row(&.{ "from", "from_type", "link", "to", "to_type", "review" });
        for (self.ctx.graph.items) |*item| {
            if (!self.included(item)) continue;
            for (item.links) |link| {
                const target = self.ctx.graph.find(link.target);
                const state = try self.ctx.reviews.stateOf(a, &self.ctx.project.schema, self.ctx.graph, item, link);
                try csv.row(&.{
                    item.id,
                    item.type_name,
                    link.type_name,
                    link.target,
                    if (target) |t| t.type_name else "",
                    if (state) |s| switch (s) {
                        .reviewed => "reviewed",
                        .never_reviewed => "never reviewed",
                        .suspect => "suspect",
                    } else "",
                });
            }
        }
        return csv.out.items;
    }

    /// One row per citation
    fn citations(self: Exporter) ![]const u8 {
        var csv: Csv = .{ .arena = self.ctx.arena };
        try csv.row(&.{ "set", "file", "line", "item", "item_type" });
        for (self.ctx.citations.all) |c| {
            const target = self.ctx.graph.find(c.target);
            if (target) |t| {
                if (!self.included(t)) continue;
            } else if (self.profile != null) continue;
            try csv.field(c.set);
            try csv.field(c.file);
            try csv.integer(c.line);
            try csv.field(c.target);
            try csv.field(if (target) |t| t.type_name else "");
            try csv.endRow();
        }
        return csv.out.items;
    }
};

test {
    _ = Csv;
    _ = @import("_test/export.zig");
}

//! What `skein check` holds the targets of other repositories (`name:id`)
//! to: links, references in items and in narrative text, and citations.
//! A repository that is not declared, an item it does not have and a
//! removed item are problems; a repository whose items could not be read
//! is a warning, since nothing about it can be known.

const std = @import("std");

const Graph = @import("../graph/Graph.zig");
const Network = @import("Network.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");

const Error = std.mem.Allocator.Error;

const Place = struct {
    file: []const u8,
    line: u32,
    column: u32,
    /// what refers: "lex.token: verifies", or "the text"
    what: []const u8,
};

const Context = struct {
    arena: std.mem.Allocator,
    network: *const Network,
    report: *Report,
    /// per repository whose items could not be read, how many targets
    unchecked: std.array_hash_map.String(u32) = .empty,

    /// Checks one target, and gives the item when there is one
    fn target(self: *Context, place: Place, t: []const u8) Error!?Network.Found {
        if (Network.split(t) == null) return null;
        const found = self.network.resolve(t);
        switch (found) {
            .undeclared => |name| try self.report.add(place.file, place.line, place.column, "{s} '{s}', and no repository '{s}' is declared ([[repositories]] in .skein/config.toml)", .{ place.what, t, name }),
            .unavailable => |m| {
                const entry = try self.unchecked.getOrPut(self.arena, m.repository.name);
                entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
            },
            .missing => |m| try self.report.add(place.file, place.line, place.column, "{s} '{s}', and {s} has no such item at {s}", .{ place.what, t, m.repository.name, m.at() }),
            .item => |f| {
                const asked = Network.split(t).?.id;
                if (!std.mem.eql(u8, asked, f.item.id)) try self.report.warn(place.file, place.line, place.column, "{s} '{s}', which is now '{s}:{s}'", .{ place.what, t, f.member.repository.name, f.item.id });
                const target_type = f.member.project.schema.itemType(f.item.type_name) orelse return found;
                if (f.item.isTombstone(target_type)) try self.report.add(place.file, place.line, place.column, "{s} '{s}', which is removed", .{ place.what, t });
            },
        }
        return found;
    }
};

/// Reports what is wrong with the targets in other repositories of the
/// items, narrative text and citations of a project.
pub fn run(arena: std.mem.Allocator, project: *const Project, graph: *const Graph, citations: *const Graph.Citations, network: *const Network, report: *Report) Error!void {
    var ctx: Context = .{ .arena = arena, .network = network, .report = report };
    for (graph.items) |*item| {
        for (item.links) |link| {
            const what = try arena.print("{s}: {s}: the link points to", .{ item.id, link.type_name });
            const found = try ctx.target(.{ .file = item.file, .line = if (link.line > 0) link.line else item.line, .column = 1, .what = what }, link.target) orelse continue;
            if (found != .item) continue;
            const link_type = project.schema.linkType(link.type_name) orelse continue;
            const type_name = found.item.item.type_name;
            if (link_type.to.len > 0 and !Schema.names.contains(link_type.to, type_name)) {
                try report.add(item.file, if (link.line > 0) link.line else item.line, 1, "{s}: {s}: '{s}' is a '{s}', which this link cannot point to", .{ item.id, link.type_name, link.target, type_name });
            }
        }
        for (item.references) |r| {
            const what = try arena.print("{s}: the text refers to", .{item.id});
            _ = try ctx.target(.{ .file = item.file, .line = r.line, .column = r.column, .what = what }, r.target);
        }
    }
    for (graph.mentions) |m| {
        _ = try ctx.target(.{ .file = m.file, .line = m.line, .column = m.column, .what = "the text refers to" }, m.target);
    }
    for (citations.all) |c| {
        const found = try ctx.target(.{ .file = c.file, .line = c.line, .column = c.column, .what = "the citation names" }, c.target) orelse continue;
        if (found != .item) continue;
        const set = project.citationSet(c.set) orelse continue;
        const type_name = found.item.item.type_name;
        if (set.to.len > 0 and !Schema.names.contains(set.to, type_name)) {
            try report.add(c.file, c.line, c.column, "the citation names '{s}', a '{s}', which '{s}' citations do not cite", .{ c.target, type_name, set.name });
        }
    }
    for (ctx.unchecked.keys(), ctx.unchecked.values()) |name, n| {
        const m = network.member(name).?;
        try report.warn(Project.config_file, 0, 0, "repositories: {s}: {s}, so {d} reference{s} to it {s} not checked", .{ name, m.unavailable.?, n, if (n == 1) "" else "s", if (n == 1) "is" else "are" });
    }
}

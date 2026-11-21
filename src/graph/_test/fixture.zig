//! A small schema and the plumbing the graph's tests share.

const std = @import("std");
const testing = std.testing;

const Graph = @import("../Graph.zig");
const Report = @import("../../Report.zig");
const Schema = @import("../../schema/Schema.zig");
const documents = @import("../documents.zig");
const item_file = @import("../item_file.zig");

/// Rules (in documents, with categories and a stage), numbered
/// requirements, tests that verify rules, and terms.
pub const schema: Schema = .{
    .types = &.{
        .{
            .name = "rule",
            .categories = &.{ "syntax", "legality" },
            .attributes = &.{
                .{ .name = "stage", .values = &.{ "s0", "s1" } },
                .{ .name = "since", .kind = .date },
                .{ .name = "weight", .kind = .integer },
                .{ .name = "final", .kind = .boolean },
            },
        },
        .{
            .name = "srs",
            .id = .{ .numbered = .{ .prefix = "SRS" } },
            .verification = &.{ "test", "analysis" },
            .attributes = &.{.{ .name = "priority", .values = &.{ "low", "high" }, .required = true }},
        },
        .{ .name = "term" },
        .{ .name = "test", .statuses = &.{ "active", "retired" }, .tombstone = "retired" },
    },
    .links = &.{
        .{ .name = "verifies", .from = &.{"test"}, .to = &.{ "rule", "srs" }, .required = true },
        .{ .name = "refines", .from = &.{"srs"}, .to = &.{"srs"} },
        .{ .name = "see" },
    },
};

pub const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    report: Report,
    items: std.ArrayList(Graph.Item) = .empty,
    mentions: std.ArrayList(Graph.Mention) = .empty,

    pub fn init(self: *Fixture) void {
        self.arena = .init(testing.allocator);
        self.report = .{ .arena = self.arena.allocator() };
        self.items = .empty;
        self.mentions = .empty;
    }

    pub fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }

    pub fn document(self: *Fixture, file: []const u8, source: []const u8) !void {
        try documents.read(self.arena.allocator(), &schema, &self.report, file, source, &self.items, &self.mentions);
    }

    pub fn itemFile(self: *Fixture, file: []const u8, source: []const u8, default_type: ?[]const u8) !void {
        const a = self.arena.allocator();
        if (try item_file.read(a, &schema, &self.report, file, source, default_type)) |item| try self.items.append(a, item);
    }

    /// The graph of what was read, checked
    pub fn check(self: *Fixture) !Graph {
        var graph = try Graph.init(self.arena.allocator(), self.items.items, &self.report);
        graph.mentions = self.mentions.items;
        try Graph.checks.run(&graph, &schema, &self.report);
        return graph;
    }

    pub fn expectProblems(self: *Fixture, expected: []const u8) !void {
        try testing.expectEqualStrings(expected, try self.report.render(self.arena.allocator()));
    }
};

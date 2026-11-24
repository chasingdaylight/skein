//! `skein/graph`: the network of items and their links, for the editor's
//! graph view: each item with its type, status, source and the profiles it
//! is in; each link with its type and, where links of its type are
//! reviewed, whether it is reviewed, suspect or never reviewed. An item of
//! another repository that a link points to is a node of its own.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Graph = @import("../graph/Graph.zig");
const Network = @import("../network/Network.zig");
const Report = @import("../Report.zig");
const Server = @import("Server.zig");
const coverage = @import("../graph/coverage.zig");
const describe = @import("../output/describe.zig");
const generated = @import("../render/generated.zig");
const views = @import("views.zig");

const Node = struct {
    id: []const u8,
    type: []const u8,
    status: []const u8 = "",
    title: []const u8 = "",
    uri: []const u8 = "",
    line: usize = 0,
    source: []const u8 = "",
    profiles: []const []const u8 = &.{},
    /// the repository of an item of another one; empty for this one's
    repository: []const u8 = "",
};

const Edge = struct {
    from: []const u8,
    to: []const u8,
    type: []const u8,
    /// "reviewed", "suspect", "never reviewed", or empty where links of the
    /// type are not reviewed
    state: []const u8 = "",
};

pub fn graph(s: *Server, a: Allocator, id: json.Value) Server.Error!void {
    var ws = s.open(a) orelse return s.respond(a, id, null);
    defer ws.close();
    if (!ws.items_read) return s.respond(a, id, null);
    const schema = &ws.project.schema;
    var ignored: Report = .{ .arena = a };
    const reviews = try Graph.Reviews.load(s.io, a, ws.root, &ignored);
    const approvals = try Graph.Approvals.load(s.io, a, ws.root, &ignored);
    const ctx: describe.Context = .{ .arena = a, .project = &ws.project, .graph = &ws.graph, .citations = &ws.citations, .reviews = &reviews, .approvals = &approvals };

    var nodes: std.ArrayList(Node) = .empty;
    var edges: std.ArrayList(Edge) = .empty;
    var others: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (ws.graph.items) |*item| {
        const t = schema.itemType(item.type_name) orelse continue;
        if (item.isTombstone(t)) continue;
        var profiles: std.ArrayList([]const u8) = .empty;
        for (schema.profiles) |*p| if (coverage.inProfile(p, item, t)) try profiles.append(a, p.name);
        const first = generated.firstParagraph(item.text);
        try nodes.append(a, .{
            .id = item.id,
            .type = item.type_name,
            .status = item.effectiveStatus(t),
            .title = first[0 .. std.mem.findScalar(u8, first, '\n') orelse first.len],
            .uri = try s.uriOf(a, &ws, item.file),
            .line = if (item.line > 0) item.line - 1 else 0,
            .source = views.sourceOf(&ws, item.file),
            .profiles = profiles.items,
        });
        for (item.links) |link| {
            const target = if (ws.graph.find(link.target) orelse ws.graph.formerly(link.target)) |found| found.id else link.target;
            if (Network.split(link.target)) |parts| {
                if (!(try others.getOrPut(a, link.target)).found_existing) {
                    try nodes.append(a, .{ .id = link.target, .type = "", .repository = parts.repository });
                }
            } else if (ws.graph.find(target) == null) continue;
            try edges.append(a, .{ .from = item.id, .to = target, .type = link.type_name, .state = try describe.stateName(ctx, item, link) orelse "" });
        }
    }
    var types: std.ArrayList([]const u8) = .empty;
    for (schema.types) |t| try types.append(a, t.name);
    var links: std.ArrayList([]const u8) = .empty;
    for (schema.links) |l| try links.append(a, l.name);
    var profiles: std.ArrayList([]const u8) = .empty;
    for (schema.profiles) |p| try profiles.append(a, p.name);
    var sources: std.ArrayList([]const u8) = .empty;
    for (ws.project.sources) |src| try sources.append(a, src.path);
    try s.respond(a, id, .{ .nodes = nodes.items, .edges = edges.items, .types = types.items, .links = links.items, .profiles = profiles.items, .sources = sources.items });
}

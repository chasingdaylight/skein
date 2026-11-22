//! Documents held to the maturity expected at the project's milestone:
//! a controlled document whose front matter names an item (`item`) and a
//! maturity (`maturity`) is warned of when it is below the item's value of
//! the attribute the milestone names (`[maturity] milestone = "pdr"`), in
//! the order the configuration gives (`order = ["D", "P", "B", "U", "F"]`).

const std = @import("std");
const Io = std.Io;

const Control = @import("../render/control.zig");
const Graph = @import("Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const files = @import("../files.zig");

pub fn check(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, report: *Report) !void {
    const m = project.maturity;
    const milestone = m.milestone orelse return;
    if (m.order.len == 0) return;
    for (project.sources) |source| {
        const found = files.list(io, arena, root, source.path, &.{".md"}) catch continue;
        for (found) |file| {
            const text = root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch continue;
            const doc = try Control.documentOf(arena, file, text) orelse continue;
            if (doc.item.len == 0) continue;
            const item = graph.find(doc.item) orelse {
                try report.warn(file, 1, 1, "document {s} is item '{s}', and there is no such item", .{ doc.id, doc.item });
                continue;
            };
            const expected = item.attribute(milestone) orelse continue;
            const want = m.rank(expected) orelse continue;
            if (doc.maturity.len == 0) {
                try report.warn(file, 1, 1, "document {s} gives no maturity; at {s}, {s} is expected to be at {s}", .{ doc.id, milestone, item.id, expected });
                continue;
            }
            const have = m.rank(doc.maturity) orelse {
                try report.warn(file, 1, 1, "document {s}: '{s}' is not a maturity ({s})", .{ doc.id, doc.maturity, try std.mem.join(arena, ", ", m.order) });
                continue;
            };
            if (have < want) try report.warn(file, 1, 1, "document {s} is at {s}; at {s}, {s} is expected to be at {s}", .{ doc.id, doc.maturity, milestone, item.id, expected });
        }
    }
}

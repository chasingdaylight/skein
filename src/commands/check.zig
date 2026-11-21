//! `skein check`: what is wrong with the project.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");

pub const Outcome = struct {
    /// for standard output when `ok`, else for standard error
    text: []const u8,
    ok: bool,
};

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Common) !Outcome {
    const found = Project.findRoot(io, arena, options.root) catch |e| return .{
        .text = try arena.print("skein: cannot look for a project from '{s}' ({s})\n", .{ options.root, @errorName(e) }),
        .ok = false,
    };
    const root_path = found orelse return .{
        .text = try arena.print("skein: no project here: no '{s}' directory in '{s}' or above it\n", .{ Project.dir_name, options.root }),
        .ok = false,
    };
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);

    var report: Report = .{ .arena = arena };
    const project = try Project.load(io, arena, root, &report);
    if (!report.ok()) {
        const problems = try report.render(arena);
        const n = report.problems.items.len;
        return .{
            .text = try arena.print("{s}skein: {d} problem{s}\n", .{ problems, n, if (n == 1) "" else "s" }),
            .ok = false,
        };
    }
    return .{
        .text = try arena.print("skein: {s}: no problems ({d} item types, {d} link types, {d} profiles, {d} sources)\n", .{
            if (project.name.len > 0) project.name else root_path,
            project.schema.types.len,
            project.schema.links.len,
            project.schema.profiles.len,
            project.sources.len,
        }),
        .ok = true,
    };
}

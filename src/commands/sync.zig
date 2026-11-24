//! `skein sync`: back online after working on the mirror, writes the overlay
//! to the forge (`skein apply`: a field that changed on both sides is
//! reported, not overwritten) and then refreshes the mirror from the forge.

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const apply = @import("apply.zig");
const cli = @import("../cli.zig");
const mirror = @import("mirror.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Sync) !Workspace.Outcome {
    const written = try apply.run(io, arena, .{ .common = options.common, .dry_run = options.dry_run, .force = options.force });
    if (written.status == .misuse) return written;
    if (options.dry_run) return written;
    const refreshed = try mirror.run(io, arena, .{ .common = options.common });
    const text = try arena.print("{s}{s}", .{ written.text, refreshed.text });
    // what the overlay could not write stays a problem, though the mirror is fresh
    const status: Workspace.Outcome.Status = if (refreshed.status != .ok) refreshed.status else written.status;
    return .{ .text = text, .status = status };
}

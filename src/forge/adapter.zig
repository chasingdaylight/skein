//! The adapter for the forge a project is on: what it says of an issue, and
//! writing to one. GitHub's and GitLab's are built; Forgejo's is to come.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const github = @import("github.zig");
const gitlab = @import("gitlab.zig");

/// What the forge says of `r`
pub fn lookup(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !github.Answer {
    return switch (forge.kind) {
        .github => github.lookup(io, arena, forge, r),
        .gitlab => gitlab.lookup(io, arena, forge, r),
        .forgejo => .{ .unreachable_ = "skein has no adapter for Forgejo yet" },
    };
}

/// Writes `changes` to `r`; null when it was written, else why not
pub fn update(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: github.Changes, body_path: []const u8) !?[]const u8 {
    return switch (forge.kind) {
        .github => github.update(io, arena, forge, r, changes, body_path),
        .gitlab => gitlab.update(io, arena, forge, r, changes, body_path),
        .forgejo => "skein has no adapter for Forgejo yet",
    };
}

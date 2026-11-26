//! The adapter for the forge a project is on: what it says of an issue, and
//! writing to one: GitHub's, GitLab's and Forgejo's.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const github = @import("github.zig");
const forgejo = @import("forgejo.zig");
const gitlab = @import("gitlab.zig");

/// What the forge says of `r`
pub fn lookup(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref) !github.Answer {
    return switch (forge.kind) {
        .github => github.lookup(io, arena, forge, r),
        .gitlab => gitlab.lookup(io, arena, forge, r),
        .forgejo => forgejo.lookup(io, arena, forge, r),
    };
}

/// Writes `changes` to `r`; null when it was written, else why not
pub fn update(io: Io, arena: std.mem.Allocator, forge: *const Forge, r: Forge.Ref, changes: github.Changes, body_path: []const u8) !?[]const u8 {
    return switch (forge.kind) {
        .github => github.update(io, arena, forge, r, changes, body_path),
        .gitlab => gitlab.update(io, arena, forge, r, changes, body_path),
        .forgejo => forgejo.update(io, arena, forge, r, changes, body_path),
    };
}

/// GET `path` of the forge's REST API (`repos/...` for GitHub and Forgejo, `projects/...`
/// for GitLab)
pub fn api(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8) !github.Reply {
    return switch (forge.kind) {
        .github => github.api(io, arena, forge, path),
        .gitlab => gitlab.api(io, arena, forge, path),
        .forgejo => forgejo.api(io, arena, forge, path),
    };
}

/// Sends `json` with `method` to `path` of the forge's REST API
pub fn send(io: Io, arena: std.mem.Allocator, forge: *const Forge, method: []const u8, path: []const u8, json: []const u8, body_path: []const u8) !github.Reply {
    return switch (forge.kind) {
        .github => github.send(io, arena, forge, method, path, json, body_path),
        .gitlab => gitlab.send(io, arena, forge, method, path, json, body_path),
        .forgejo => forgejo.send(io, arena, forge, method, path, json, body_path),
    };
}

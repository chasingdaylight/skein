//! `skein baseline [NAME]`: freezes the project as it is committed, as
//! an annotated git tag that names itself a baseline and says what the
//! project held then. Without a name, lists the baselines.
//!
//! The tag is made in the local repository and not pushed. Writing the
//! forge's values a plan uses before tagging is still to come (design,
//! section 6; `baselines`, planned).

const std = @import("std");
const Io = std.Io;

const check = @import("check.zig");
const cli = @import("../cli.zig");
const coverage = @import("../graph/coverage.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const Workspace = @import("Workspace.zig");

/// What the message of a baseline's tag starts with, which tells a
/// baseline from another tag
pub const mark = history.baseline_mark;

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Baseline) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (try git.output(io, arena, ws.root, &.{ "rev-parse", "--git-dir" }) == null) return misuse(arena, "the project is not in a git repository", .{});
    const name = options.name orelse return list(io, arena, &ws);

    if (!validName(name)) return misuse(arena, "'{s}' cannot be the name of a tag", .{name});
    if (try git.output(io, arena, ws.root, &.{ "rev-parse", "--verify", "--quiet", try arena.print("refs/tags/{s}", .{name}) })) |_| {
        return misuse(arena, "there is a tag '{s}' already", .{name});
    }
    // a tag holds what is committed: the project must be all of it
    const changes = try git.output(io, arena, ws.root, &.{ "status", "--porcelain", "--", "." }) orelse "";
    if (std.mem.trim(u8, changes, " \r\n").len > 0) return misuse(arena, "there are changes that are not committed; a baseline is of what is committed", .{});
    // and sound: a baseline is a state that can be built on
    try check.all(io, arena, &ws);
    if (!ws.report.ok()) {
        var problems = try ws.problems();
        problems.text = try arena.print("{s}skein: a baseline is of a project without problems\n", .{problems.text});
        return problems;
    }

    const message = try summary(arena, &ws, name, options.message);
    if (try git.output(io, arena, ws.root, &.{ "tag", "--annotate", "--no-sign", "--message", message, name, "HEAD" }) == null) {
        return misuse(arena, "git could not make the tag '{s}'", .{name});
    }
    const commit = std.mem.trim(u8, try git.output(io, arena, ws.root, &.{ "rev-parse", "--short", "HEAD" }) orelse "", " \r\n");
    return .{ .text = try arena.print("skein: baseline {s} at {s}; share it with: git push origin {s}\n", .{ name, commit, name }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

/// A name git takes for a tag, kept simple: letters, digits, `.`, `-`, `_`
/// and `/`, not starting with `-` or `.`
fn validName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '-' or name[0] == '.' or std.mem.endsWith(u8, name, ".") or std.mem.find(u8, name, "..") != null) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and std.mem.findScalar(u8, "._-/", c) == null) return false;
    }
    return true;
}

/// The message of the tag: the mark, the message given, and what the
/// project held
fn summary(arena: std.mem.Allocator, ws: *const Workspace, name: []const u8, message: ?[]const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "{s} {s}\n\n", .{ mark, name });
    if (message) |m| try out.print(arena, "{s}\n\n", .{m});
    try out.print(arena, "{s}: {d} items\n", .{ ws.name(), ws.graph.items.len });
    for (try coverage.compute(arena, &ws.project, &ws.graph, &ws.citations, null)) |e| {
        try out.print(arena, "{s} {s} of {s} items: {d} of {d}\n", .{ e.name, switch (e.kind) {
            .link => "links",
            .citation => "citations",
        }, e.item_type, e.covered, e.total });
    }
    return out.items;
}

/// The baselines, oldest first
fn list(io: Io, arena: std.mem.Allocator, ws: *const Workspace) !Workspace.Outcome {
    var out: std.ArrayList(u8) = .empty;
    for (try history.baselines(io, arena, ws.root)) |b| try out.print(arena, "{s}  {s}\n", .{ b.name, b.date });
    if (out.items.len == 0) return .{ .text = "skein: there is no baseline yet\n" };
    return .{ .text = out.items };
}

test {
    _ = @import("_test/baseline.zig");
    _ = @import("_test/gates.zig");
    _ = @import("_test/editions.zig");
}

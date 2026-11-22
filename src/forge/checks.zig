//! What `skein check` holds references to issues and pull requests to
//! (`#97`, `owner/repo#12`), when the project names its forge: each must
//! exist, and one that a link type requires open (`open = true`) must be
//! open. The forge is asked unless `--offline`; what it last said is kept,
//! and used when it cannot be reached. What cannot be checked either way
//! is a warning. Without `[forge]`, such references are accepted unchecked.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const cache = @import("cache.zig");
const github = @import("github.zig");
const history = @import("../history.zig");

/// How an issue is looked up: the forge itself, or something else in tests
pub var lookup: *const fn (Io, std.mem.Allocator, *const Forge, Forge.Ref) anyerror!github.Answer = github.lookup;

const Place = struct {
    file: []const u8,
    line: u32,
    column: u32,
    what: []const u8,
    target: []const u8,
    /// whether a link of a type that requires the issue open points there
    must_be_open: bool = false,
};

pub fn run(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, offline: bool, report: *Report) !void {
    const forge = project.forge orelse return;
    var places: std.ArrayList(Place) = .empty;
    for (graph.items) |*item| {
        for (item.links) |link| {
            if (!Forge.isRef(link.target)) continue;
            const must = if (project.schema.linkType(link.type_name)) |t| t.open else false;
            try places.append(arena, .{ .file = item.file, .line = if (link.line > 0) link.line else item.line, .column = 1, .what = try arena.print("{s}: {s}: the link points to", .{ item.id, link.type_name }), .target = link.target, .must_be_open = must });
        }
        for (item.references) |r| {
            if (Forge.isRef(r.target)) try places.append(arena, .{ .file = item.file, .line = r.line, .column = r.column, .what = try arena.print("{s}: the text refers to", .{item.id}), .target = r.target });
        }
    }
    for (graph.mentions) |m| {
        if (Forge.isRef(m.target)) try places.append(arena, .{ .file = m.file, .line = m.line, .column = m.column, .what = "the text refers to", .target = m.target });
    }
    if (places.items.len == 0) return;

    const git_dir: ?[]const u8 = history.gitDir(io, arena, root) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    // each issue is asked about once
    var answers: std.array_hash_map.String(?github.Answer) = .empty;
    var unchecked: usize = 0;
    var why: []const u8 = "";
    for (places.items) |p| {
        const r = forge.ref(p.target).?;
        const key = try arena.print("{s}#{d}", .{ r.repository, r.number });
        const entry = try answers.getOrPut(arena, key);
        if (!entry.found_existing) entry.value_ptr.* = try answer(io, arena, git_dir, &forge, r, offline, &why);
        const a = entry.value_ptr.* orelse {
            unchecked += 1;
            continue;
        };
        switch (a) {
            .missing => try report.add(p.file, p.line, p.column, "{s} '{s}', and {s} has no such issue or pull request", .{ p.what, p.target, r.repository }),
            .found => |issue| if (p.must_be_open and !issue.open) try report.add(p.file, p.line, p.column, "{s} '{s}', which is closed", .{ p.what, p.target }),
            .unreachable_ => unreachable,
        }
    }
    if (unchecked > 0) try report.warn(Project.config_file, 0, 0, "forge: {d} reference{s} to issues and pull requests {s} not checked: {s}", .{ unchecked, if (unchecked == 1) "" else "s", if (unchecked == 1) "is" else "are", why });
}

/// What is known of `r`: the forge's answer, else the cache's; null, with
/// the reason in `why`, when neither knows
fn answer(io: Io, arena: std.mem.Allocator, git_dir: ?[]const u8, forge: *const Forge, r: Forge.Ref, offline: bool, why: *[]const u8) !?github.Answer {
    if (!offline) {
        const a = lookup(io, arena, forge, r) catch |e| github.Answer{ .unreachable_ = try arena.print("the forge could not be asked ({t})", .{e}) };
        switch (a) {
            .unreachable_ => |reason| why.* = reason,
            else => {
                if (git_dir) |d| try cache.put(io, arena, d, forge, r, a);
                return a;
            },
        }
    } else why.* = "offline, and the cache does not have them";
    if (git_dir) |d| if (try cache.get(io, arena, d, forge, r)) |cached| return cached;
    return null;
}

test {
    _ = Forge;
    _ = github;
    _ = @import("_test/checks.zig");
}

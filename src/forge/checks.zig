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
const adapter = @import("adapter.zig");
const cache = @import("cache.zig");
const github = @import("github.zig");
const history = @import("../history.zig");

/// How an issue is looked up: the forge itself, or something else in tests
pub var lookup: *const fn (Io, std.mem.Allocator, *const Forge, Forge.Ref) anyerror!github.Answer = adapter.lookup;

/// How an issue is written: the forge itself, or something else in tests
pub var update: *const fn (Io, std.mem.Allocator, *const Forge, Forge.Ref, github.Changes, []const u8) anyerror!?[]const u8 = adapter.update;

const Place = struct {
    file: []const u8,
    line: u32,
    column: u32,
    what: []const u8,
    target: []const u8,
    /// whether a link of a type that requires the issue open points there
    must_be_open: bool = false,
};

/// Where the project names issues and pull requests
fn placesOf(arena: std.mem.Allocator, project: *const Project, graph: *const Graph) ![]const Place {
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
    return places.items;
}

/// What is known of the issues and pull requests a project names: what
/// the forge said, else its cache, each asked about once
pub const Known = struct {
    forge: Forge,
    /// by "owner/repo#N"; null when nothing is known
    answers: std.array_hash_map.String(?github.Answer) = .empty,
    /// why some are not known
    why: []const u8 = "",

    /// What is known of `target`, which names an issue or pull request
    pub fn of(self: *const Known, arena: std.mem.Allocator, target: []const u8) !?github.Answer {
        const r = self.forge.ref(target) orelse return null;
        return self.answers.get(try key(arena, r)) orelse null;
    }
};

fn key(arena: std.mem.Allocator, r: Forge.Ref) ![]const u8 {
    return arena.print("{s}#{d}", .{ r.repository, r.number });
}

/// What can be learned of the issues and pull requests `graph` names; null
/// when the project names no forge
pub fn learn(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, offline: bool) !?Known {
    return learnOf(io, arena, root, project, try placesOf(arena, project, graph), offline);
}

/// What can be learned of the issues and pull requests `targets` name
/// (`#12`); null when the project names no forge
pub fn learnRefs(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, targets: []const []const u8, offline: bool) !?Known {
    var places: std.ArrayList(Place) = .empty;
    for (targets) |t| {
        if (!Forge.isRef(t)) continue;
        try places.append(arena, .{ .file = "", .line = 0, .column = 0, .what = "", .target = t });
    }
    return learnOf(io, arena, root, project, places.items, offline);
}

fn learnOf(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, places: []const Place, offline: bool) !?Known {
    var known: Known = .{ .forge = project.forge orelse return null };
    if (places.len == 0) return known;
    const git_dir: ?[]const u8 = history.gitDir(io, arena, root) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    for (places) |p| {
        const r = known.forge.ref(p.target).?;
        const entry = try known.answers.getOrPut(arena, try key(arena, r));
        if (!entry.found_existing) entry.value_ptr.* = try answer(io, arena, git_dir, &known.forge, r, offline, &known.why);
    }
    return known;
}

pub fn run(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, graph: *const Graph, offline: bool, report: *Report) !void {
    const places = try placesOf(arena, project, graph);
    const known = try learnOf(io, arena, root, project, places, offline) orelse return;
    var unchecked: usize = 0;
    const why = known.why;
    for (places) |p| {
        const r = known.forge.ref(p.target).?;
        const a = try known.of(arena, p.target) orelse {
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
    _ = @import("pulls.zig");
    _ = @import("_test/pulls.zig");
}

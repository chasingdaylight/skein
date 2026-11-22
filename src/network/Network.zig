//! The other repositories a project's items refer to (`name:id`), each
//! read at the state of the network the project records
//! (`.skein/network.toml`), at the commit checked out there now
//! (`--current`), or as its files are on disk (`--working`).

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Item = @import("../graph/Item.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const fingerprint = @import("../graph/fingerprint.zig");
const git = @import("../git.zig");
const history = @import("../history.zig");
const record = @import("record.zig");

const Network = @This();

members: []const Member = &.{},

pub const State = enum {
    /// the commits `.skein/network.toml` records
    recorded,
    /// the commit each checkout has checked out
    current,
    /// each checkout's files as they are, committed or not
    working,
};

pub const Member = struct {
    repository: Project.Repository,
    /// the commit read; null for files read as they are on disk
    commit: ?[]const u8 = null,
    project: Project = .{},
    graph: Graph = .{},
    /// why its items could not be read; null when they were
    unavailable: ?[]const u8 = null,

    /// The commit, short, for messages
    pub fn at(self: *const Member) []const u8 {
        const c = self.commit orelse return "its working tree";
        return c[0..@min(c.len, 12)];
    }
};

pub const Found = union(enum) {
    item: struct { member: *const Member, item: *const Item },
    /// the project declares no repository of that name
    undeclared: []const u8,
    /// the repository's items could not be read
    unavailable: *const Member,
    /// the repository has no such item
    missing: *const Member,
};

/// The repository's name and the ID in it, of a target `name:id`; null
/// for a target of this repository
pub fn split(target: []const u8) ?struct { repository: []const u8, id: []const u8 } {
    const colon = std.mem.findScalar(u8, target, ':') orelse return null;
    return .{ .repository = target[0..colon], .id = target[colon + 1 ..] };
}

pub fn member(self: *const Network, name: []const u8) ?*const Member {
    for (self.members) |*m| {
        if (std.mem.eql(u8, m.repository.name, name)) return m;
    }
    return null;
}

/// What the target `name:id` is
pub fn resolve(self: *const Network, target: []const u8) Found {
    const parts = split(target) orelse unreachable;
    const m = self.member(parts.repository) orelse return .{ .undeclared = parts.repository };
    if (m.unavailable != null) return .{ .unavailable = m };
    const item = m.graph.find(parts.id) orelse return .{ .missing = m };
    return .{ .item = .{ .member = m, .item = item } };
}

/// Reads the repositories `project` declares, in the state `state`. What
/// cannot be read is a member with the reason; a record that does not
/// match the commit it names is reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, root_path: []const u8, project: *const Project, state: State, report: *Report) !Network {
    if (project.repositories.len == 0) return .{};
    const entries = try record.read(io, arena, root, report);
    // snapshots go into this repository's git directory, never another's
    const scratch: ?[]const u8 = if (history.gitDir(io, arena, root)) |dir| try Io.Dir.path.join(arena, &.{ dir, "skein", "snapshots" }) else |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    var members: std.ArrayList(Member) = .empty;
    for (project.repositories) |repository| {
        var m: Member = .{ .repository = repository };
        try read(io, arena, root_path, scratch, entries, state, &m);
        if (state == .recorded and m.unavailable == null) {
            const entry = record.find(entries, repository.name).?;
            const now = try ofProject(arena, &m.graph, &m.project.schema);
            if (!std.mem.eql(u8, now, entry.fingerprint)) {
                try report.add(record.file, 0, 0, "{s}: its items at {s} are not those that were pinned; pin it again ('skein pin {s}')", .{ repository.name, m.at(), repository.name });
            }
        }
        try members.append(arena, m);
    }
    return .{ .members = members.items };
}

/// Fills in `m`: its commit and its items, or why they cannot be read
fn read(io: Io, arena: std.mem.Allocator, root_path: []const u8, scratch: ?[]const u8, entries: []const record.Entry, state: State, m: *Member) !void {
    const path = m.repository.path orelse {
        m.unavailable = "a repository with a url is not fetched yet; give the path of a checkout";
        return;
    };
    var dir = Io.Dir.cwd().openDir(io, try Io.Dir.path.join(arena, &.{ root_path, path }), .{}) catch {
        m.unavailable = try arena.print("there is no checkout at '{s}'", .{path});
        return;
    };
    defer dir.close(io);
    var ignored: Report = .{ .arena = arena };
    switch (state) {
        .working => {
            m.project = try Project.load(io, arena, dir, &ignored);
            m.graph = try Graph.load(io, arena, dir, &m.project, &ignored);
        },
        .recorded, .current => {
            const revision = if (state == .current) "HEAD" else if (record.find(entries, m.repository.name)) |e| e.commit else {
                m.unavailable = try arena.print("it is not pinned yet ('skein pin {s}')", .{m.repository.name});
                return;
            };
            const where = scratch orelse {
                m.unavailable = "the project is not in a git repository, which reading a commit needs";
                return;
            };
            var snap = history.snapshotIn(io, arena, dir, revision, try Io.Dir.path.join(arena, &.{ where, m.repository.name })) catch |e| {
                m.unavailable = switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.NoGit => try arena.print("'{s}' is not a git repository", .{path}),
                    error.UnknownRevision => try arena.print("its checkout has no commit {s}; fetch it there", .{revision[0..@min(revision.len, 12)]}),
                    error.SnapshotFailed => "its files at that commit could not be unpacked",
                };
                return;
            };
            defer snap.deinit();
            m.commit = snap.commit;
            m.project = snap.project;
            m.graph = snap.graph;
        },
    }
}

/// The fingerprint of all the items of a project: over each item's ID and
/// fingerprint, in order of ID, in hexadecimal
pub fn ofProject(arena: std.mem.Allocator, graph: *const Graph, schema: *const Schema) std.mem.Allocator.Error![]const u8 {
    const ids = try arena.alloc([]const u8, graph.items.len);
    for (graph.items, ids) |*item, *id| id.* = item.id;
    std.mem.sort([]const u8, ids, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    for (ids) |id| {
        const fp = try fingerprint.of(arena, graph, schema, graph.find(id).?);
        hash.update(id);
        hash.update(" ");
        hash.update(&fp);
        hash.update("\n");
    }
    const hex = std.fmt.bytesToHex(hash.finalResult(), .lower);
    return arena.dupe(u8, &hex);
}

test {
    _ = record;
    _ = @import("_test/network.zig");
}

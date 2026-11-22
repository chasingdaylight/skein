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
const fetch = @import("fetch.zig");
const identity = @import("identity.zig");
const record = @import("record.zig");

const Network = @This();

members: []const Member = &.{},
/// the project's own record
recorded: record.Record = .{},

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
    /// whether it is a git submodule of the project, whose commit git records
    submodule: bool = false,
    /// its own record of its network, as it was at the commit read
    recorded: record.Record = .{},

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

pub const Options = struct {
    state: State = .recorded,
    /// fetch nothing: a repository by `url` is read from its cache alone
    offline: bool = false,
};

/// Where a repository's commits are read from: its checkout, or the cache
/// of a repository by `url`
pub const Origin = struct {
    dir: Io.Dir,
    /// whether it is the cache of a `url`
    fetched: bool,
};

/// The origin of `repository`, or why there is none
pub fn origin(io: Io, arena: std.mem.Allocator, root_path: []const u8, git_dir: ?[]const u8, repository: Project.Repository) !union(enum) { ok: Origin, failed: []const u8 } {
    if (repository.path) |path| {
        const dir = Io.Dir.cwd().openDir(io, try Io.Dir.path.join(arena, &.{ root_path, path }), .{}) catch
            return .{ .failed = try arena.print("there is no checkout at '{s}'", .{path}) };
        return .{ .ok = .{ .dir = dir, .fetched = false } };
    }
    const where = git_dir orelse return .{ .failed = "the project is not in a git repository, which fetching needs" };
    const dir = try fetch.cache(io, arena, where, repository.name) orelse return .{ .failed = "its cache under .git/skein could not be made" };
    return .{ .ok = .{ .dir = dir, .fetched = true } };
}

/// Reads the repositories `project` declares, in the state `options`
/// asks for. What cannot be read is a member with the reason; a record
/// that does not match the commit it names is reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, root_path: []const u8, project: *const Project, options: Options, report: *Report) !Network {
    if (project.repositories.len == 0) return .{};
    const own = try record.read(io, arena, root, report);
    const entries = own.entries;
    // snapshots and caches go into this repository's git directory, never another's
    const git_dir: ?[]const u8 = history.gitDir(io, arena, root) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    var members: std.ArrayList(Member) = .empty;
    for (project.repositories) |repository| {
        var m: Member = .{ .repository = repository };
        try read(io, arena, root, root_path, git_dir, entries, options, &m);
        if (options.state == .recorded and m.unavailable == null and !m.submodule) {
            const entry = record.find(entries, repository.name).?;
            const now = try ofProject(arena, &m.graph, &m.project.schema);
            if (!std.mem.eql(u8, now, entry.fingerprint)) {
                try report.add(record.file, 0, 0, "{s}: its items at {s} are not those that were pinned; pin it again ('skein pin {s}')", .{ repository.name, m.at(), repository.name });
            }
        }
        try members.append(arena, m);
    }
    const out: Network = .{ .members = members.items, .recorded = own };
    try identity.check(&out, project, report);
    return out;
}

/// The commit a submodule of `root` at `path` is recorded at, in git's
/// index; null when `path` is no submodule
pub fn submoduleCommit(io: Io, arena: std.mem.Allocator, root: Io.Dir, path: []const u8) !?[]const u8 {
    if (std.mem.find(u8, path, "..") != null) return null;
    const out = try git.output(io, arena, root, &.{ "ls-files", "--stage", "--", path }) orelse return null;
    // "160000 <commit> 0\t<path>" for a gitlink
    if (!std.mem.startsWith(u8, out, "160000 ")) return null;
    var words = std.mem.tokenizeAny(u8, out, " \t\n");
    _ = words.next();
    return words.next();
}

/// Fills in `m`: its commit and its items, or why they cannot be read
fn read(io: Io, arena: std.mem.Allocator, root: Io.Dir, root_path: []const u8, git_dir: ?[]const u8, entries: []const record.Entry, options: Options, m: *Member) !void {
    const name = m.repository.name;
    var o = switch (try origin(io, arena, root_path, git_dir, m.repository)) {
        .ok => |o| o,
        .failed => |why| {
            m.unavailable = why;
            return;
        },
    };
    defer o.dir.close(io);
    var ignored: Report = .{ .arena = arena };
    if (options.state == .working and !o.fetched) {
        m.project = try Project.load(io, arena, o.dir, &ignored);
        m.graph = try Graph.load(io, arena, o.dir, &m.project, &ignored);
        m.recorded = try record.read(io, arena, o.dir, &ignored);
        return;
    }
    const gitlink = if (o.fetched) null else try submoduleCommit(io, arena, root, m.repository.path.?);
    const revision: []const u8 = switch (options.state) {
        // a submodule is recorded by git itself
        .recorded => if (gitlink) |c| blk: {
            m.submodule = true;
            break :blk c;
        } else blk: {
            const entry = record.find(entries, name) orelse {
                m.unavailable = try arena.print("it is not pinned yet ('skein pin {s}')", .{name});
                return;
            };
            if (o.fetched and !try fetch.commit(io, arena, o.dir, m.repository.url.?, entry.commit, options.offline)) {
                m.unavailable = try notFetched(arena, m.repository, options.offline, entry.commit);
                return;
            }
            break :blk entry.commit;
        },
        // a repository by url has no working tree: its tip is as near as it gets
        .current, .working => if (!o.fetched) "HEAD" else try fetch.tip(io, arena, o.dir, m.repository.url.?, m.repository.ref, options.offline) orelse {
            m.unavailable = try notFetched(arena, m.repository, options.offline, null);
            return;
        },
    };
    const scratch = try Io.Dir.path.join(arena, &.{ git_dir orelse {
        m.unavailable = "the project is not in a git repository, which reading a commit needs";
        return;
    }, "skein", "snapshots", name });
    var snap = history.snapshotIn(io, arena, o.dir, revision, scratch) catch |e| {
        m.unavailable = switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoGit => try arena.print("'{s}' is not a git repository", .{m.repository.path orelse name}),
            error.UnknownRevision => try arena.print("its checkout has no commit {s}; fetch it there", .{revision[0..@min(revision.len, 12)]}),
            error.SnapshotFailed => "its files at that commit could not be unpacked",
        };
        return;
    };
    defer snap.deinit();
    m.submodule = gitlink != null;
    m.commit = snap.commit;
    m.project = snap.project;
    m.graph = snap.graph;
    m.recorded = try record.read(io, arena, snap.dir, &ignored);
}

/// Why a repository by url could not be read: offline, or not fetched
pub fn notFetched(arena: std.mem.Allocator, repository: Project.Repository, offline: bool, commit: ?[]const u8) ![]const u8 {
    const what = if (commit) |c| try arena.print("the commit {s}", .{c[0..@min(c.len, 12)]}) else "its tip";
    if (offline) return arena.print("offline, and {s} is not in its cache", .{what});
    return arena.print("{s} could not be fetched from {s}", .{ what, repository.url.? });
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
    _ = fetch;
    _ = @import("_test/network.zig");
}

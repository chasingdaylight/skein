//! What every command that works on a project starts with: the project's
//! root, its configuration and schema, and its items.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Graph = @import("../graph/Graph.zig");
const Network = @import("../network/Network.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");

const Workspace = @This();

/// What a command gives back: text for standard output and exit status
/// 0, or text for standard error and a status that says what kind of
/// failure it was.
pub const Outcome = struct {
    text: []const u8,
    status: Status = .ok,

    pub const Status = enum(u8) {
        ok = 0,
        /// the project has problems
        problems = 1,
        /// the command was not used as it must be
        misuse = 2,
    };
};

io: Io,
arena: std.mem.Allocator,
root: Io.Dir,
root_path: []const u8,
project: Project,
graph: Graph,
citations: Graph.Citations = .{},
/// the other repositories, in the state the command asks for
network: Network = .{},
/// whether the configuration and schema were sound, so the items were read
items_read: bool = false,
report: Report,

pub const Opened = union(enum) {
    ok: Workspace,
    /// there is no project to open; say this and stop
    failed: Outcome,
};

/// Finds the project from `common.root` and reads its configuration,
/// schema and items. Their problems are in the workspace's report; the
/// items are read only when the configuration and schema have none.
pub fn open(io: Io, arena: std.mem.Allocator, common: cli.Common) !Opened {
    const found = Project.findRoot(io, arena, common.root) catch |e| return .{ .failed = .{
        .text = try arena.print("skein: cannot look for a project from '{s}' ({s})\n", .{ common.root, @errorName(e) }),
        .status = .misuse,
    } };
    const root_path = found orelse return .{ .failed = .{
        .text = try arena.print("skein: no project here: no '{s}' directory in '{s}' or above it\n", .{ Project.dir_name, common.root }),
        .status = .misuse,
    } };
    var self: Workspace = .{
        .io = io,
        .arena = arena,
        .root = try Io.Dir.cwd().openDir(io, root_path, .{}),
        .root_path = root_path,
        .project = undefined,
        .graph = .{},
        .report = .{ .arena = arena },
    };
    self.project = try Project.load(io, arena, self.root, &self.report);
    // items are read against the schema: a broken one would only add noise
    if (self.report.ok()) {
        self.items_read = true;
        self.graph = try Graph.load(io, arena, self.root, &self.project, &self.report);
        self.citations = try Graph.Citations.load(io, arena, self.root, &self.project, &self.report);
        self.network = try Network.load(io, arena, self.root, root_path, &self.project, .{ .state = common.state, .offline = common.offline }, &self.report);
        // the workspace is returned by value: the graph points at a copy that stays put
        const others = try arena.create(Network);
        others.* = self.network;
        self.graph.others = others;
    }
    return .{ .ok = self };
}

pub fn close(self: *Workspace) void {
    self.root.close(self.io);
}

/// The project's name, for messages
pub fn name(self: *const Workspace) []const u8 {
    return if (self.project.name.len > 0) self.project.name else self.root_path;
}

/// The problems found so far, as a command's outcome
pub fn problems(self: *Workspace) !Outcome {
    const text = try self.report.render(self.arena);
    const n = self.report.problems.items.len;
    return .{
        .text = try self.arena.print("{s}skein: {d} problem{s}{s}\n", .{ text, n, if (n == 1) "" else "s", try self.warningCount() }),
        .status = .problems,
    };
}

/// ", 2 warnings", or nothing when there are none
pub fn warningCount(self: *const Workspace) ![]const u8 {
    const w = self.report.warnings.items.len;
    if (w == 0) return "";
    return self.arena.print(", {d} warning{s}", .{ w, if (w == 1) "" else "s" });
}

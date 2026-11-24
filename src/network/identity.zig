//! Who the repositories of a network are: the identities they declare
//! (`[project] id`), whatever short names other projects give them. So a
//! repository reached by two paths is known to be one, and where a
//! member's own record has it at another commit than this network, that
//! is said: the project skein is run for decides.

const std = @import("std");

const Network = @import("Network.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const record = @import("record.zig");

const Error = std.mem.Allocator.Error;

/// Reports a repository declared twice under two names (a problem) and a
/// member whose record has a repository at another commit than this
/// network has it (a warning).
pub fn check(network: *const Network, project: *const Project, report: *Report) Error!void {
    const members = network.members;
    for (members, 0..) |*a, i| {
        if (a.unavailable != null) continue;
        const id = a.project.id orelse continue;
        if (project.id) |own| if (std.mem.eql(u8, own, id)) {
            try report.add(Project.config_file, 0, 0, "repositories: {s}: it is this project ({s})", .{ a.repository.name, id });
        };
        for (members[i + 1 ..]) |*b| {
            const other = b.project.id orelse continue;
            if (std.mem.eql(u8, id, other)) try report.add(Project.config_file, 0, 0, "repositories: {s} and {s} are the same repository ({s})", .{ a.repository.name, b.repository.name, id });
        }
    }
    for (members) |*m| {
        if (m.unavailable != null) continue;
        for (m.recorded.entries) |e| try compare(network, project, report, m, e.id orelse continue, e.commit);
        for (m.recorded.reached) |r| try compare(network, project, report, m, r.id, r.commit);
    }
}

fn compare(network: *const Network, project: *const Project, report: *Report, m: *const Network.Member, id: []const u8, commit: []const u8) Error!void {
    // a member may cite this project in turn; this project is read as it is
    if (project.id) |own| if (std.mem.eql(u8, own, id)) return;
    const ours = commitOf(network, id) orelse return;
    if (std.mem.eql(u8, ours, commit)) return;
    try report.warn(Project.config_file, 0, 0, "repositories: {s}: its own record has {s} at {s}, and this network has it at {s}, which is what is read here", .{ m.repository.name, id, short(commit), short(ours) });
}

/// The commit this network has the repository `id` at: a member's, or one
/// reached through them; null when it has none
pub fn commitOf(network: *const Network, id: []const u8) ?[]const u8 {
    for (network.members) |*m| {
        const mine = m.project.id orelse continue;
        if (std.mem.eql(u8, mine, id)) return m.commit;
    }
    for (network.recorded.reached) |r| {
        if (std.mem.eql(u8, r.id, id)) return r.commit;
    }
    return null;
}

/// One declared repository, with what it says of its own network
pub const Source = struct {
    name: []const u8,
    /// what it calls itself
    id: ?[]const u8,
    record: record.Record,
};

/// The repositories reached through `sources` and not declared here, each
/// once, at the commit their records give: the reached part of this
/// project's record. Two sources that record one at different commits are
/// reported, and it is left out.
pub fn reached(arena: std.mem.Allocator, project: *const Project, sources: []const Source, report: *Report) Error![]const record.Reached {
    var out: std.ArrayList(record.Reached) = .empty;
    var through: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    var refused: std.ArrayList([]const u8) = .empty;
    for (sources) |s| {
        var named: std.ArrayList(record.Reached) = .empty;
        for (s.record.entries) |e| if (e.id) |id| try named.append(arena, .{ .id = id, .commit = e.commit, .through = &.{} });
        try named.appendSlice(arena, s.record.reached);
        next: for (named.items) |n| {
            if (project.id) |own| if (std.mem.eql(u8, own, n.id)) continue;
            for (sources) |d| if (d.id) |did| if (std.mem.eql(u8, did, n.id)) continue :next;
            for (refused.items) |r| if (std.mem.eql(u8, r, n.id)) continue :next;
            for (out.items, through.items, 0..) |*have, *by, i| {
                if (!std.mem.eql(u8, have.id, n.id)) continue;
                if (!std.mem.eql(u8, have.commit, n.commit)) {
                    try report.add(Project.config_file, 0, 0, "repositories: {s} and {s} record {s} at different commits ({s}, {s}); pin one of them again so that they agree", .{ by.items[0], s.name, n.id, short(have.commit), short(n.commit) });
                    try refused.append(arena, n.id);
                    _ = out.orderedRemove(i);
                    _ = through.orderedRemove(i);
                } else try by.append(arena, s.name);
                continue :next;
            }
            try out.append(arena, .{ .id = n.id, .commit = n.commit, .through = &.{} });
            var by: std.ArrayList([]const u8) = .empty;
            try by.append(arena, s.name);
            try through.append(arena, by);
        }
    }
    for (out.items, through.items) |*r, by| r.through = by.items;
    return out.items;
}

fn short(commit: []const u8) []const u8 {
    return commit[0..@min(commit.len, 12)];
}

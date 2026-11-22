//! Reading everything a forge holds of a project's issues, pull requests,
//! milestones and labels, through its REST API, as a `Mirror.Data`.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const Mirror = @import("Mirror.zig");
const adapter = @import("adapter.zig");
const github = @import("github.zig");
const pulls = @import("pulls.zig");

/// How the forge's API is asked: the forge itself, or something else in tests
pub var call: *const fn (Io, std.mem.Allocator, *const Forge, []const u8) anyerror!github.Reply = adapter.api;

pub const Fetched = union(enum) {
    data: Mirror.Data,
    /// why the forge could not be read
    failed: []const u8,
};

const Json = std.json.Value;

/// Everything the forge holds of `forge.repository`
pub fn fetch(io: Io, arena: std.mem.Allocator, forge: *const Forge) !Fetched {
    const lab = forge.kind == .gitlab;
    const base = if (lab) try arena.print("projects/{s}", .{try std.mem.replaceOwned(u8, arena, forge.repository, "/", "%2F")}) else try arena.print("repos/{s}", .{forge.repository});

    var failed: []const u8 = "";
    const raw_issues = try pages(io, arena, forge, try arena.print("{s}/issues?state=all", .{base}), &failed);
    if (failed.len > 0) return .{ .failed = failed };
    const raw_milestones = try pages(io, arena, forge, try arena.print("{s}/milestones?state=all", .{base}), &failed);
    if (failed.len > 0) return .{ .failed = failed };
    const raw_labels = try pages(io, arena, forge, try arena.print("{s}/labels", .{base}), &failed);
    if (failed.len > 0) return .{ .failed = failed };

    var issues: std.ArrayList(Mirror.Issue) = .empty;
    for (raw_issues) |v| {
        if (!lab and v == .object and v.object.get("pull_request") != null) {
            try issues.append(arena, try issueOf(arena, v, true, false));
        } else try issues.append(arena, try issueOf(arena, v, false, lab));
    }
    if (lab) {
        const raw_merges = try pages(io, arena, forge, try arena.print("{s}/merge_requests?state=all", .{base}), &failed);
        if (failed.len > 0) return .{ .failed = failed };
        for (raw_merges) |v| try issues.append(arena, try issueOf(arena, v, true, true));
    }

    // the comments: GitHub gives all of a repository's at once, GitLab one issue's at a time
    if (lab) {
        for (issues.items) |*i| {
            const kind = if (i.pull) "merge_requests" else "issues";
            const notes = try pages(io, arena, forge, try arena.print("{s}/{s}/{d}/notes?sort=asc", .{ base, kind, i.number }), &failed);
            if (failed.len > 0) return .{ .failed = failed };
            i.comments = try notesOf(arena, notes);
        }
    } else {
        const raw_comments = try pages(io, arena, forge, try arena.print("{s}/issues/comments", .{base}), &failed);
        if (failed.len > 0) return .{ .failed = failed };
        try attach(arena, issues.items, raw_comments);
    }

    // who approved and when it was merged
    for (issues.items) |*i| {
        if (!i.pull) continue;
        switch (try pulls.get(io, arena, forge, i.number)) {
            .pull => |p| {
                i.merged = p.merged_on;
                i.approvers = p.approvers;
            },
            .missing => {},
            .unreachable_ => |why| return .{ .failed = why },
        }
    }
    std.mem.sort(Mirror.Issue, issues.items, {}, struct {
        fn lt(_: void, a: Mirror.Issue, b: Mirror.Issue) bool {
            return a.number < b.number;
        }
    }.lt);

    var milestones: std.ArrayList(Mirror.Milestone) = .empty;
    for (raw_milestones) |v| if (v == .object) {
        const o = v.object;
        try milestones.append(arena, .{
            // GitHub numbers milestones; GitLab's per-project number is `iid`
            .number = intOf(o.get("iid") orelse o.get("number")),
            .title = strOf(o.get("title")),
            .description = strOf(o.get("description")),
            .open = !(std.mem.eql(u8, strOf(o.get("state")), "closed")),
            .due = day(o.get("due_on") orelse o.get("due_date")),
        });
    };
    var labels: std.ArrayList(Mirror.Label) = .empty;
    for (raw_labels) |v| if (v == .object) {
        try labels.append(arena, .{ .name = strOf(v.object.get("name")), .color = std.mem.trimStart(u8, strOf(v.object.get("color")), "#"), .description = strOf(v.object.get("description")) });
    };
    return .{ .data = .{ .kind = forge.kind, .repository = forge.repository, .url = forge.url, .issues = issues.items, .milestones = milestones.items, .labels = labels.items } };
}

/// All the elements of a paged list `path` of the API; `failed` says why when it could not be read
fn pages(io: Io, arena: std.mem.Allocator, forge: *const Forge, path: []const u8, failed: *[]const u8) ![]const Json {
    var out: std.ArrayList(Json) = .empty;
    const joiner: []const u8 = if (std.mem.findScalar(u8, path, '?') != null) "&" else "?";
    var page: usize = 1;
    while (page <= 1000) : (page += 1) {
        const reply = try call(io, arena, forge, try arena.print("{s}{s}per_page=100&page={d}", .{ path, joiner, page }));
        const text = switch (reply) {
            .body => |t| t,
            .missing => {
                failed.* = try arena.print("the forge has no {s}", .{path});
                return out.items;
            },
            .unreachable_ => |why| {
                failed.* = why;
                return out.items;
            },
        };
        const v = std.json.parseFromSliceLeaky(Json, arena, text, .{}) catch {
            failed.* = "the forge gave an answer skein cannot read";
            return out.items;
        };
        if (v != .array) {
            failed.* = "the forge gave an answer skein cannot read";
            return out.items;
        }
        try out.appendSlice(arena, v.array.items);
        if (v.array.items.len < 100) break;
    }
    return out.items;
}

fn issueOf(arena: std.mem.Allocator, v: Json, pull: bool, lab: bool) !Mirror.Issue {
    const o = if (v == .object) v.object else return .{ .number = 0, .title = "", .open = true };
    const state = strOf(o.get("state"));
    var labels: std.ArrayList([]const u8) = .empty;
    if (o.get("labels")) |ls| if (ls == .array) {
        // GitHub: objects with a name; GitLab: names
        for (ls.array.items) |l| {
            if (l == .string) try labels.append(arena, l.string) else if (l == .object) try labels.append(arena, strOf(l.object.get("name")));
        }
    };
    var assignees: std.ArrayList([]const u8) = .empty;
    if (o.get("assignees")) |as| if (as == .array) {
        for (as.array.items) |a| if (a == .object) try assignees.append(arena, strOf(a.object.get(if (lab) "username" else "login")));
    };
    const author = if (o.get("user") orelse o.get("author")) |u| (if (u == .object) strOf(u.object.get(if (lab) "username" else "login")) else "") else "";
    const milestone = if (o.get("milestone")) |m| (if (m == .object) strOf(m.object.get("title")) else "") else "";
    return .{
        .number = intOf(o.get(if (lab) "iid" else "number")),
        .pull = pull,
        .title = strOf(o.get("title")),
        .open = std.mem.eql(u8, state, "open") or std.mem.eql(u8, state, "opened"),
        .author = author,
        .created = strOf(o.get("created_at")),
        .updated = strOf(o.get("updated_at")),
        .labels = labels.items,
        .assignees = assignees.items,
        .milestone = if (milestone.len > 0) milestone else null,
        .body = strOf(o.get(if (lab) "description" else "body")),
    };
}

/// GitHub's comments, each of which says its issue's address (`.../issues/12`)
fn attach(arena: std.mem.Allocator, issues: []Mirror.Issue, raw: []const Json) !void {
    var by: std.array_hash_map.Auto(u64, std.ArrayList(Mirror.Comment)) = .empty;
    for (raw) |c| {
        if (c != .object) continue;
        const url = strOf(c.object.get("issue_url"));
        const slash = std.mem.findScalarLast(u8, url, '/') orelse continue;
        const number = std.fmt.parseInt(u64, url[slash + 1 ..], 10) catch continue;
        const user = if (c.object.get("user")) |u| (if (u == .object) strOf(u.object.get("login")) else "") else "";
        const entry = try by.getOrPut(arena, number);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(arena, .{ .author = user, .created = strOf(c.object.get("created_at")), .body = strOf(c.object.get("body")) });
    }
    for (issues) |*i| if (by.get(i.number)) |list| {
        i.comments = list.items;
    };
}

/// GitLab's notes of one issue: the people's, not the system's ("changed the description")
fn notesOf(arena: std.mem.Allocator, raw: []const Json) ![]const Mirror.Comment {
    var out: std.ArrayList(Mirror.Comment) = .empty;
    for (raw) |n| {
        if (n != .object) continue;
        if (n.object.get("system")) |s| if (s == .bool and s.bool) continue;
        const user = if (n.object.get("author")) |u| (if (u == .object) strOf(u.object.get("username")) else "") else "";
        try out.append(arena, .{ .author = user, .created = strOf(n.object.get("created_at")), .body = strOf(n.object.get("body")) });
    }
    return out.items;
}

fn strOf(v: ?Json) []const u8 {
    const x = v orelse return "";
    return if (x == .string) x.string else "";
}

fn intOf(v: ?Json) u64 {
    const x = v orelse return 0;
    return if (x == .integer and x.integer >= 0) @intCast(x.integer) else 0;
}

/// `2027-03-12T07:00:00Z` or `2027-03-12` as its day
fn day(v: ?Json) ?[]const u8 {
    const s = strOf(v);
    return if (s.len >= 10) s[0..10] else null;
}

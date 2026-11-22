//! A full mirror of a forge's issues, pull requests, milestones and labels,
//! in forge-neutral plain text under `.skein/mirror/` (`skein mirror`): for
//! working offline for long, and as the form `skein publish` moves a project
//! to another forge in. One file per issue (`issues/12.toml`) and pull request
//! (`pulls/12.toml`), one per milestone, and the labels in one file.

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const github = @import("github.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const dir = ".skein/mirror";

pub const Comment = struct {
    author: []const u8,
    created: []const u8,
    body: []const u8,
};

/// An issue, or a pull or merge request
pub const Issue = struct {
    number: u64,
    pull: bool = false,
    title: []const u8,
    open: bool,
    author: []const u8 = "",
    created: []const u8 = "",
    updated: []const u8 = "",
    labels: []const []const u8 = &.{},
    assignees: []const []const u8 = &.{},
    milestone: ?[]const u8 = null,
    body: []const u8 = "",
    comments: []const Comment = &.{},
    /// a pull request: the day it was merged, and who approved it
    merged: ?[]const u8 = null,
    approvers: []const []const u8 = &.{},
};

pub const Milestone = struct {
    number: u64,
    title: []const u8,
    description: []const u8 = "",
    open: bool = true,
    /// `YYYY-MM-DD`
    due: ?[]const u8 = null,
};

pub const Label = struct {
    name: []const u8,
    color: []const u8 = "",
    description: []const u8 = "",
};

pub const Data = struct {
    kind: Forge.Kind,
    /// `owner/repo`
    repository: []const u8,
    url: ?[]const u8 = null,
    issues: []const Issue = &.{},
    milestones: []const Milestone = &.{},
    labels: []const Label = &.{},
};

/// Writes `data` as the mirror under `root`, replacing what was mirrored; the
/// directory ignores itself in git unless `committed`
pub fn save(io: Io, arena: std.mem.Allocator, root: Io.Dir, data: Data, committed: bool) !void {
    root.deleteTree(io, dir) catch {};
    try root.createDirPath(io, dir ++ "/issues");
    try root.createDirPath(io, dir ++ "/pulls");
    try root.createDirPath(io, dir ++ "/milestones");
    if (!committed) try root.writeFile(io, .{ .sub_path = dir ++ "/.gitignore", .data = "*\n" });
    var head: std.ArrayList(u8) = .empty;
    try head.print(arena, "# A mirror of the forge: written by skein mirror, read by skein; not edited.\nkind = {s}\nrepository = {s}\n", .{ try write.string(arena, @tagName(data.kind)), try write.string(arena, data.repository) });
    if (data.url) |u| try head.print(arena, "url = {s}\n", .{try write.string(arena, u)});
    try root.writeFile(io, .{ .sub_path = dir ++ "/mirror.toml", .data = head.items });
    for (data.issues) |i| {
        const sub = try arena.print("{s}/{s}/{d}.toml", .{ dir, if (i.pull) "pulls" else "issues", i.number });
        try root.writeFile(io, .{ .sub_path = sub, .data = try issueText(arena, i) });
    }
    for (data.milestones) |m| {
        const sub = try arena.print("{s}/milestones/{d}.toml", .{ dir, m.number });
        try root.writeFile(io, .{ .sub_path = sub, .data = try milestoneText(arena, m) });
    }
    var labels: std.ArrayList(u8) = .empty;
    try labels.appendSlice(arena, "# The labels of the forge.\n");
    for (data.labels) |l| try labels.print(arena, "\n[[labels]]\nname = {s}\ncolor = {s}\ndescription = {s}\n", .{ try write.string(arena, l.name), try write.string(arena, l.color), try write.string(arena, l.description) });
    try root.writeFile(io, .{ .sub_path = dir ++ "/labels.toml", .data = labels.items });
}

fn issueText(arena: std.mem.Allocator, i: Issue) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "number = {d}\ntitle = {s}\nstate = {s}\nauthor = {s}\ncreated = {s}\nupdated = {s}\n", .{ i.number, try write.string(arena, i.title), if (i.open) "\"open\"" else "\"closed\"", try write.string(arena, i.author), try write.string(arena, i.created), try write.string(arena, i.updated) });
    try out.print(arena, "labels = {s}\nassignees = {s}\n", .{ try write.strings(arena, i.labels), try write.strings(arena, i.assignees) });
    if (i.milestone) |m| try out.print(arena, "milestone = {s}\n", .{try write.string(arena, m)});
    if (i.merged) |d| try out.print(arena, "merged = {s}\napprovers = {s}\n", .{ try write.string(arena, d), try write.strings(arena, i.approvers) });
    try out.print(arena, "body = {s}\n", .{try write.string(arena, i.body)});
    for (i.comments) |c| try out.print(arena, "\n[[comments]]\nauthor = {s}\ncreated = {s}\nbody = {s}\n", .{ try write.string(arena, c.author), try write.string(arena, c.created), try write.string(arena, c.body) });
    return out.items;
}

fn milestoneText(arena: std.mem.Allocator, m: Milestone) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "number = {d}\ntitle = {s}\nstate = {s}\ndescription = {s}\n", .{ m.number, try write.string(arena, m.title), if (m.open) "\"open\"" else "\"closed\"", try write.string(arena, m.description) });
    if (m.due) |d| try out.print(arena, "due = {s}\n", .{try write.string(arena, d)});
    return out.items;
}

/// The mirror under `root`; null when there is none
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir) !?Data {
    const head = (try table(io, arena, root, dir ++ "/mirror.toml")) orelse return null;
    const kind = std.meta.stringToEnum(Forge.Kind, str(head, "kind") orelse return null) orelse return null;
    var issues: std.ArrayList(Issue) = .empty;
    for ([_][]const u8{ "issues", "pulls" }) |sub| {
        for (try names(io, arena, root, try arena.print("{s}/{s}", .{ dir, sub }))) |name| {
            const t = (try table(io, arena, root, try arena.print("{s}/{s}/{s}", .{ dir, sub, name }))) orelse continue;
            try issues.append(arena, try issueOf(arena, t, std.mem.eql(u8, sub, "pulls")));
        }
    }
    std.mem.sort(Issue, issues.items, {}, struct {
        fn lt(_: void, a: Issue, b: Issue) bool {
            return a.number < b.number;
        }
    }.lt);
    var milestones: std.ArrayList(Milestone) = .empty;
    for (try names(io, arena, root, dir ++ "/milestones")) |name| {
        const t = (try table(io, arena, root, try arena.print("{s}/milestones/{s}", .{ dir, name }))) orelse continue;
        try milestones.append(arena, .{ .number = num(t, "number"), .title = str(t, "title") orelse "", .description = str(t, "description") orelse "", .open = !std.mem.eql(u8, str(t, "state") orelse "open", "closed"), .due = str(t, "due") });
    }
    var labels: std.ArrayList(Label) = .empty;
    if (try table(io, arena, root, dir ++ "/labels.toml")) |t| if (t.get("labels")) |ls| if (ls == .array) {
        for (ls.array.values()) |l| if (l == .table) try labels.append(arena, .{ .name = str(l.table, "name") orelse "", .color = str(l.table, "color") orelse "", .description = str(l.table, "description") orelse "" });
    };
    return .{ .kind = kind, .repository = str(head, "repository") orelse return null, .url = str(head, "url"), .issues = issues.items, .milestones = milestones.items, .labels = labels.items };
}

fn issueOf(arena: std.mem.Allocator, t: *const toml.Table, pull: bool) !Issue {
    var comments: std.ArrayList(Comment) = .empty;
    if (t.get("comments")) |cs| if (cs == .array) {
        for (cs.array.values()) |c| if (c == .table) try comments.append(arena, .{ .author = str(c.table, "author") orelse "", .created = str(c.table, "created") orelse "", .body = str(c.table, "body") orelse "" });
    };
    return .{
        .number = num(t, "number"),
        .pull = pull,
        .title = str(t, "title") orelse "",
        .open = !std.mem.eql(u8, str(t, "state") orelse "open", "closed"),
        .author = str(t, "author") orelse "",
        .created = str(t, "created") orelse "",
        .updated = str(t, "updated") orelse "",
        .labels = try list(arena, t, "labels"),
        .assignees = try list(arena, t, "assignees"),
        .milestone = str(t, "milestone"),
        .body = str(t, "body") orelse "",
        .comments = comments.items,
        .merged = str(t, "merged"),
        .approvers = try list(arena, t, "approvers"),
    };
}

fn table(io: Io, arena: std.mem.Allocator, root: Io.Dir, path: []const u8) !?*toml.Table {
    const text = root.readFileAlloc(io, path, arena, .limited(1 << 24)) catch return null;
    var diag: toml.Diagnostic = .{};
    return toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return null,
    };
}

/// The names of the files in `path`, in order
fn names(io: Io, arena: std.mem.Allocator, root: Io.Dir, path: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var d = root.openDir(io, path, .{ .iterate = true }) catch return out.items;
    defer d.close(io);
    var it = d.iterate();
    // a directory that cannot be listed through is a mirror that is not there
    while (it.next(io) catch null) |e| {
        if (e.kind == .file and std.mem.endsWith(u8, e.name, ".toml")) try out.append(arena, try arena.dupe(u8, e.name));
    }
    std.mem.sort([]const u8, out.items, {}, lessThan);
    return out.items;
}

/// by number, so `9.toml` comes before `10.toml`
fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    const x = std.fmt.parseInt(u64, a[0 .. a.len - ".toml".len], 10) catch return std.mem.lessThan(u8, a, b);
    const y = std.fmt.parseInt(u64, b[0 .. b.len - ".toml".len], 10) catch return std.mem.lessThan(u8, a, b);
    return x < y;
}

fn str(t: *const toml.Table, key: []const u8) ?[]const u8 {
    const v = t.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn num(t: *const toml.Table, key: []const u8) u64 {
    const v = t.get(key) orelse return 0;
    return if (v == .integer and v.integer >= 0) @intCast(v.integer) else 0;
}

fn list(arena: std.mem.Allocator, t: *const toml.Table, key: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    if (t.get(key)) |v| if (v == .array) {
        for (v.array.values()) |x| if (x == .string) try out.append(arena, x.string);
    };
    return out.items;
}

/// What the mirror says of issue `r` of the project's own repository; null
/// when there is no mirror or it does not have the issue
pub fn answer(io: Io, arena: std.mem.Allocator, root: Io.Dir, r: Forge.Ref) !?github.Answer {
    const head = (try table(io, arena, root, dir ++ "/mirror.toml")) orelse return null;
    if (!std.mem.eql(u8, str(head, "repository") orelse "", r.repository)) return null;
    for ([_][]const u8{ "issues", "pulls" }) |sub| {
        const t = (try table(io, arena, root, try arena.print("{s}/{s}/{d}.toml", .{ dir, sub, r.number }))) orelse continue;
        const i = try issueOf(arena, t, std.mem.eql(u8, sub, "pulls"));
        var due: ?[]const u8 = null;
        if (i.milestone) |m| due = try milestoneDue(io, arena, root, m);
        return .{ .found = .{ .title = i.title, .open = i.open, .pull = i.pull, .assignees = i.assignees, .milestone = i.milestone, .due = due } };
    }
    return null;
}

fn milestoneDue(io: Io, arena: std.mem.Allocator, root: Io.Dir, title: []const u8) !?[]const u8 {
    for (try names(io, arena, root, dir ++ "/milestones")) |name| {
        const t = (try table(io, arena, root, try arena.print("{s}/milestones/{s}", .{ dir, name }))) orelse continue;
        if (std.mem.eql(u8, str(t, "title") orelse "", title)) return str(t, "due");
    }
    return null;
}

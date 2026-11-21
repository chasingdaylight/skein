//! `skein diff [REV [REV]]`: which items were added, removed or changed
//! since a commit (default: the last one), or between two.
//! `skein impact [REV]`: the same, and what the changes reach in the
//! project as it is now.

const std = @import("std");
const Io = std.Io;

const cli = @import("../cli.zig");
const Json = @import("../output/Json.zig");
const Reviews = @import("../graph/Reviews.zig");
const Workspace = @import("Workspace.zig");
const changes = @import("../graph/changes.zig");
const history = @import("../history.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Diff) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const from = if (options.revisions.len > 0) options.revisions[0] else "HEAD";
    var old = history.snapshot(io, arena, ws.root, from) catch |e| return failed(arena, from, e);
    defer old.deinit();
    const old_side: changes.Side = .{ .graph = &old.graph, .schema = &old.project.schema };

    // the other side: a second commit, or the files as they are
    var to: []const u8 = "the working tree";
    var newer: ?history.Snapshot = null;
    defer if (newer) |*n| n.deinit();
    if (options.revisions.len > 1) {
        to = options.revisions[1];
        newer = history.snapshot(io, arena, ws.root, to) catch |e| return failed(arena, to, e);
    }
    const new_side: changes.Side = if (newer) |*n| .{ .graph = &n.graph, .schema = &n.project.schema } else .{ .graph = &ws.graph, .schema = &ws.project.schema };

    const found = try changes.compute(arena, old_side, new_side);
    var view: View = .{ .arena = arena, .from = from, .to = to, .changes = found, .markdown = options.markdown };
    if (options.impact) {
        var ignored: @import("../Report.zig") = .{ .arena = arena };
        const reviews = try Reviews.load(io, arena, ws.root, &ignored);
        view.impact = .{ .reached = try changes.reached(arena, &ws.graph, found) };
        var suspect: std.ArrayList(Suspect) = .empty;
        var cited: std.ArrayList(Cited) = .empty;
        for (found) |c| {
            if (!c.matters()) continue;
            for (ws.graph.items) |*item| {
                for (item.links) |link| {
                    if (!std.mem.eql(u8, link.target, c.id)) continue;
                    const state = try reviews.stateOf(arena, &ws.project.schema, &ws.graph, item, link) orelse continue;
                    if (state == .suspect) try suspect.append(arena, .{ .from = item.id, .link_type = link.type_name, .target = c.id });
                }
            }
            for (try ws.citations.of(arena, c.id)) |citation| {
                try cited.append(arena, .{ .set = citation.set, .file = citation.file, .line = citation.line, .target = c.id });
            }
        }
        view.impact.?.suspect = suspect.items;
        view.impact.?.cited = cited.items;
    }
    return .{ .text = if (options.json) try view.json() else try view.text() };
}

fn failed(arena: std.mem.Allocator, revision: []const u8, e: history.Error) !Workspace.Outcome {
    return .{
        .text = switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NoGit => "skein: this needs git, and a git repository\n",
            error.UnknownRevision => try arena.print("skein: git knows no commit '{s}'\n", .{revision}),
            error.SnapshotFailed => try arena.print("skein: could not take the files of '{s}' out of git\n", .{revision}),
        },
        .status = .misuse,
    };
}

const Suspect = struct { from: []const u8, link_type: []const u8, target: []const u8 };
const Cited = struct { set: []const u8, file: []const u8, line: u32, target: []const u8 };

const Impact = struct {
    reached: []const changes.Reached,
    suspect: []const Suspect = &.{},
    cited: []const Cited = &.{},
};

/// What was found, and how to show it
const View = struct {
    arena: std.mem.Allocator,
    from: []const u8,
    to: []const u8,
    changes: []const changes.Change,
    impact: ?Impact = null,
    /// headings and lists as Markdown, for a pull request
    markdown: bool,

    fn count(self: View, kind: changes.Change.Kind) usize {
        var n: usize = 0;
        for (self.changes) |c| {
            if (c.kind == kind) n += 1;
        }
        return n;
    }

    fn text(self: View) ![]const u8 {
        const a = self.arena;
        var out: std.ArrayList(u8) = .empty;
        const title = if (self.impact != null) "Impact of the changes" else "Changes";
        try out.print(a, "{s}{s} from {s} to {s}\n", .{ if (self.markdown) "## " else "", title, self.from, self.to });
        if (self.changes.len == 0) try out.appendSlice(a, "\nNo item was added, removed or changed.\n");

        inline for (.{ .{ changes.Change.Kind.added, "Added" }, .{ changes.Change.Kind.removed, "Removed" }, .{ changes.Change.Kind.changed, "Changed" } }) |group| {
            const n = self.count(group[0]);
            if (n > 0) try self.heading(&out, group[1], n);
            for (self.changes) |c| {
                if (c.kind != group[0]) continue;
                try self.entry(&out, c.id);
                try out.print(a, "  ({s})", .{c.type_name});
                for (c.what, 0..) |what, i| try out.print(a, "{s}{s}", .{ if (i == 0) "  " else ", ", what });
                if (c.kind != .removed) try out.print(a, "  {s}:{d}", .{ c.file, c.line });
                try out.append(a, '\n');
            }
        }

        const impact = self.impact orelse return out.items;
        if (impact.reached.len > 0) try self.heading(&out, "Look again at", impact.reached.len);
        for (impact.reached) |r| {
            try self.entry(&out, r.item.id);
            try out.print(a, "  ({s})  {s} {s}  {s}:{d}\n", .{ r.item.type_name, if (r.by_reference) "refers to" else "rests on", r.because, r.item.file, r.item.line });
        }
        if (impact.suspect.len > 0) try self.heading(&out, "Links now suspect", impact.suspect.len);
        for (impact.suspect) |s| {
            try self.entry(&out, s.from);
            try out.print(a, "  {s} {s}\n", .{ s.link_type, s.target });
        }
        if (impact.cited.len > 0) try self.heading(&out, "Cited in", impact.cited.len);
        for (impact.cited) |c| {
            try out.print(a, "{s}{s}:{d}  ({s})  {s}\n", .{ if (self.markdown) "- " else "  ", c.file, c.line, c.set, c.target });
        }
        if (self.changes.len > 0 and impact.reached.len == 0 and impact.suspect.len == 0 and impact.cited.len == 0) {
            try out.appendSlice(a, "\nNothing rests on what changed.\n");
        }
        return out.items;
    }

    fn heading(self: View, out: *std.ArrayList(u8), name: []const u8, n: usize) !void {
        try out.print(self.arena, "\n{s}{s} ({d}){s}\n", .{ if (self.markdown) "### " else "", name, n, if (self.markdown) "\n" else ":" });
    }

    /// The start of a line about the item `id`
    fn entry(self: View, out: *std.ArrayList(u8), id: []const u8) !void {
        if (self.markdown) try out.print(self.arena, "- `{s}`", .{id}) else try out.print(self.arena, "  {s}", .{id});
    }

    fn json(self: View) ![]const u8 {
        var j: Json = .{ .arena = self.arena };
        try j.beginObject();
        try j.key("from");
        try j.string(self.from);
        try j.key("to");
        try j.string(self.to);
        try j.key("changes");
        try j.beginArray();
        for (self.changes) |c| {
            try j.beginObject();
            try j.key("id");
            try j.string(c.id);
            try j.key("change");
            try j.string(@tagName(c.kind));
            try j.key("type");
            try j.string(c.type_name);
            try j.key("what");
            try j.strings(c.what);
            try j.key("file");
            try j.string(c.file);
            try j.key("line");
            try j.integer(c.line);
            try j.endObject();
        }
        try j.endArray();
        if (self.impact) |impact| {
            try j.key("look_again");
            try j.beginArray();
            for (impact.reached) |r| {
                try j.beginObject();
                try j.key("id");
                try j.string(r.item.id);
                try j.key("because");
                try j.string(r.because);
                try j.key("by");
                try j.string(if (r.by_reference) "reference" else "link");
                try j.endObject();
            }
            try j.endArray();
            try j.key("suspect");
            try j.beginArray();
            for (impact.suspect) |s| {
                try j.beginObject();
                try j.key("from");
                try j.string(s.from);
                try j.key("type");
                try j.string(s.link_type);
                try j.key("target");
                try j.string(s.target);
                try j.endObject();
            }
            try j.endArray();
            try j.key("cited");
            try j.beginArray();
            for (impact.cited) |c| {
                try j.beginObject();
                try j.key("set");
                try j.string(c.set);
                try j.key("file");
                try j.string(c.file);
                try j.key("line");
                try j.integer(c.line);
                try j.key("target");
                try j.string(c.target);
                try j.endObject();
            }
            try j.endArray();
        }
        try j.endObject();
        return j.finish();
    }
};

test {
    _ = @import("_test/diff.zig");
}

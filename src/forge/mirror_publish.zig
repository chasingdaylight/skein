//! Re-creating a mirror's labels, milestones, issues and comments on another
//! forge (`skein publish`), through its adapter, with a map from the old
//! references to the new. Pull and merge requests are not re-created: a
//! forge cannot make one without its branches. People are not assigned, as
//! the other forge may not know them; an issue says who opened it and when.
//! Forgejo takes GitHub's paths and fields, but names an issue's labels and
//! milestone by the ids it gave them (#299).

const std = @import("std");
const Io = std.Io;

const Forge = @import("Forge.zig");
const Mirror = @import("Mirror.zig");
const adapter = @import("adapter.zig");
const github = @import("github.zig");

/// How a request is sent: the forge itself, or something else in tests
pub var send: *const fn (Io, std.mem.Allocator, *const Forge, []const u8, []const u8, []const u8, []const u8) anyerror!github.Reply = adapter.send;

/// The wait after each write to GitHub, which takes at most 80 new things a minute
pub var pause: Io.Duration = .fromSeconds(1);

pub const Published = struct {
    labels: usize = 0,
    milestones: usize = 0,
    issues: usize = 0,
    comments: usize = 0,
    /// pull and merge requests left out
    skipped: usize = 0,
    /// `kind:owner/repo#old` and the new reference, in order
    map: []const Mapped = &.{},
    /// why it stopped, when it did
    failed: ?[]const u8 = null,
};

pub const Mapped = struct { from: []const u8, to: []const u8 };

/// Creates what `data` holds on `target`; with `dry_run` only counts it
pub fn publish(io: Io, arena: std.mem.Allocator, data: Mirror.Data, target: *const Forge, body_path: []const u8, dry_run: bool) !Published {
    var out: Published = .{};
    var map: std.ArrayList(Mapped) = .empty;
    const lab = target.kind == .gitlab;
    const jo = target.kind == .forgejo;
    const base = if (lab) try arena.print("projects/{s}", .{try std.mem.replaceOwned(u8, arena, target.repository, "/", "%2F")}) else try arena.print("repos/{s}", .{target.repository});

    // Forgejo's ids of the labels, by name
    var label_ids: std.array_hash_map.String(u64) = .empty;
    for (data.labels) |l| {
        out.labels += 1;
        if (dry_run) continue;
        const body = if (lab or jo)
            try arena.print("{{\"name\":{f},\"color\":{f},\"description\":{f}}}", .{ js(l.name), js(try arena.print("#{s}", .{if (l.color.len > 0) l.color else "cccccc"})), js(l.description) })
        else
            try arena.print("{{\"name\":{f},\"color\":{f},\"description\":{f}}}", .{ js(l.name), js(if (l.color.len > 0) l.color else "cccccc"), js(l.description) });
        // a label the forge has already is no failure
        switch (try write(io, arena, target, "POST", try arena.print("{s}/labels", .{base}), body, body_path)) {
            .body => |t| if (jo) if (idOf(arena, t, "id")) |n| try label_ids.put(arena, l.name, n),
            .missing => {},
            .unreachable_ => |why| if (!exists(why)) return stop(&out, map.items, why),
        }
    }

    // titles to the numbers the target gives
    var numbers: std.array_hash_map.String(u64) = .empty;
    for (data.milestones) |m| {
        out.milestones += 1;
        if (dry_run) continue;
        const body = if (lab)
            try arena.print("{{\"title\":{f},\"description\":{f}{s}}}", .{ js(m.title), js(m.description), try dueField(arena, m.due, true) })
        else
            try arena.print("{{\"title\":{f},\"description\":{f},\"state\":\"{s}\"{s}}}", .{ js(m.title), js(m.description), if (m.open) "open" else "closed", try dueField(arena, m.due, false) });
        switch (try write(io, arena, target, "POST", try arena.print("{s}/milestones", .{base}), body, body_path)) {
            .body => |t| if (idOf(arena, t, if (lab or jo) "id" else "number")) |n| try numbers.put(arena, m.title, n),
            .missing => {},
            .unreachable_ => |why| return stop(&out, map.items, why),
        }
    }

    for (data.issues) |i| {
        if (i.pull) {
            out.skipped += 1;
            continue;
        }
        out.issues += 1;
        if (dry_run) {
            out.comments += i.comments.len;
            continue;
        }
        const text = try arena.print("{s}\n\n---\nMirrored from {s}#{d}, opened by {s} on {s}.", .{ i.body, data.repository, i.number, if (i.author.len > 0) i.author else "someone", i.created });
        var body: std.ArrayList(u8) = .empty;
        try body.print(arena, "{{\"title\":{f},\"{s}\":{f}", .{ js(i.title), if (lab) "description" else "body", js(text) });
        if (lab) {
            try body.print(arena, ",\"labels\":{f}", .{js(try std.mem.join(arena, ",", i.labels))});
            if (i.milestone) |m| if (numbers.get(m)) |n| try body.print(arena, ",\"milestone_id\":{d}", .{n});
        } else if (jo) {
            try body.appendSlice(arena, ",\"labels\":[");
            var k: usize = 0;
            for (i.labels) |l| if (label_ids.get(l)) |id| {
                try body.print(arena, "{s}{d}", .{ if (k > 0) "," else "", id });
                k += 1;
            };
            try body.append(arena, ']');
            if (i.milestone) |m| if (numbers.get(m)) |n| try body.print(arena, ",\"milestone\":{d}", .{n});
        } else {
            try body.appendSlice(arena, ",\"labels\":[");
            for (i.labels, 0..) |l, k| try body.print(arena, "{s}{f}", .{ if (k > 0) "," else "", js(l) });
            try body.append(arena, ']');
            if (i.milestone) |m| if (numbers.get(m)) |n| try body.print(arena, ",\"milestone\":{d}", .{n});
        }
        try body.append(arena, '}');
        const created = switch (try write(io, arena, target, "POST", try arena.print("{s}/issues", .{base}), body.items, body_path)) {
            .body => |t| idOf(arena, t, if (lab) "iid" else "number") orelse return stop(&out, map.items, "the forge's answer to a new issue cannot be read"),
            .missing => return stop(&out, map.items, "the forge has no such place for issues"),
            .unreachable_ => |why| return stop(&out, map.items, why),
        };
        try map.append(arena, .{
            .from = try arena.print("{s}:{s}#{d}", .{ @tagName(data.kind), data.repository, i.number }),
            .to = try arena.print("{s}:{s}#{d}", .{ @tagName(target.kind), target.repository, created }),
        });
        for (i.comments) |c| {
            const note = try arena.print("{{\"body\":{f}}}", .{js(try arena.print("**{s}** on {s}:\n\n{s}", .{ c.author, c.created, c.body }))});
            const path = try arena.print("{s}/issues/{d}/{s}", .{ base, created, if (lab) "notes" else "comments" });
            switch (try write(io, arena, target, "POST", path, note, body_path)) {
                .body, .missing => out.comments += 1,
                .unreachable_ => |why| return stop(&out, map.items, why),
            }
        }
        if (!i.open) {
            const close = if (lab) "{\"state_event\":\"close\"}" else "{\"state\":\"closed\"}";
            const method: []const u8 = if (lab) "PUT" else "PATCH";
            switch (try write(io, arena, target, method, try arena.print("{s}/issues/{d}", .{ base, created }), close, body_path)) {
                .body, .missing => {},
                .unreachable_ => |why| return stop(&out, map.items, why),
            }
        }
    }
    out.map = map.items;
    return out;
}

/// One write, paced on GitHub
fn write(io: Io, arena: std.mem.Allocator, target: *const Forge, method: []const u8, path: []const u8, body: []const u8, body_path: []const u8) !github.Reply {
    const reply = try send(io, arena, target, method, path, body, body_path);
    if (target.kind == .github) try io.sleep(pause, .awake);
    return reply;
}

fn stop(out: *Published, map: []const Mapped, why: []const u8) Published {
    out.map = map;
    out.failed = why;
    return out.*;
}

/// A reason that says the thing is there already
fn exists(why: []const u8) bool {
    return std.mem.find(u8, why, "already_exists") != null or std.mem.find(u8, why, "already exists") != null or std.mem.find(u8, why, "has already been taken") != null;
}

fn dueField(arena: std.mem.Allocator, due: ?[]const u8, lab: bool) ![]const u8 {
    const d = due orelse return "";
    // GitHub keeps the day of the time in US Pacific time: noon UTC is the same day there
    return if (lab) try arena.print(",\"due_date\":\"{s}\"", .{d}) else try arena.print(",\"due_on\":\"{s}T12:00:00Z\"", .{d});
}

/// The number the target gave a new thing, from its JSON answer
fn idOf(arena: std.mem.Allocator, text: []const u8, key: []const u8) ?u64 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch return null;
    if (v != .object) return null;
    const n = v.object.get(key) orelse return null;
    return if (n == .integer and n.integer >= 0) @intCast(n.integer) else null;
}

fn js(s: []const u8) @TypeOf(std.json.fmt(s, .{})) {
    return std.json.fmt(s, .{});
}

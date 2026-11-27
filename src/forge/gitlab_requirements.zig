//! GitLab's requirements (Ultimate) beside Skein's items, through the files
//! GitLab reads and writes (#240): a CSV for its requirements import, the
//! map from item IDs to the requirement IIDs GitLab gave them (read from
//! its CSV export, kept in `.skein/gitlab-requirements.toml`), and the
//! requirements report a CI job uploads (`artifacts: reports:
//! requirements:`), which marks each requirement satisfied or failed. Git
//! stays the truth: GitLab's requirements are a view of the items.

const std = @import("std");
const Io = std.Io;

const Csv = @import("../output/Csv.zig");
const Graph = @import("../graph/Graph.zig");
const Results = @import("../results/Results.zig");
const csv = @import("../import/csv.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const map_file = ".skein/gitlab-requirements.toml";

/// GitLab's title has room for 255 characters
const title_limit = 255;

pub const Entry = struct { id: []const u8, iid: u64 };

/// The rows of GitLab's requirements import, `title,description`: the
/// title is the item's ID, a colon and its first sentence, so that the
/// export GitLab gives back can be matched to the items
pub fn importCsv(arena: std.mem.Allocator, items: []const *const Graph.Item) ![]const u8 {
    var out: Csv = .{ .arena = arena };
    try out.row(&.{ "title", "description" });
    for (items) |item| {
        try out.field(try title(arena, item));
        try out.field(item.text);
        try out.endRow();
    }
    return out.out.items;
}

/// `ID: first sentence`, cut to GitLab's limit
pub fn title(arena: std.mem.Allocator, item: *const Graph.Item) ![]const u8 {
    const named = item.attribute("title");
    const line_end = std.mem.findAny(u8, item.text, "\r\n") orelse item.text.len;
    var first = named orelse item.text[0..line_end];
    if (named == null) if (std.mem.find(u8, first, ". ")) |dot| {
        first = first[0 .. dot + 1];
    };
    first = std.mem.trim(u8, first, " \t");
    var t = if (first.len > 0) try arena.print("{s}: {s}", .{ item.id, first }) else item.id;
    if (t.len > title_limit) {
        var cut: usize = title_limit - 3;
        while (cut > 0 and (t[cut] & 0xC0) == 0x80) cut -= 1;
        t = try arena.print("{s}...", .{t[0..cut]});
    }
    return t;
}

pub const Matched = struct {
    entries: []const Entry,
    /// rows whose title names no item
    unmatched: []const []const u8,
};

/// The IIDs of GitLab's CSV export (`Requirement ID`, `Title`, `State`)
/// whose titles start with an item's ID, or a former one; archived
/// requirements are left out
pub fn matchExport(arena: std.mem.Allocator, text: []const u8, graph: *const Graph) !?Matched {
    const rows = csv.parse(arena, text) catch return null;
    if (rows.len == 0) return null;
    const id_col = column(rows[0], "Requirement ID") orelse return null;
    const title_col = column(rows[0], "Title") orelse return null;
    const state_col = column(rows[0], "State");
    var entries: std.ArrayList(Entry) = .empty;
    var unmatched: std.ArrayList([]const u8) = .empty;
    for (rows[1..]) |r| {
        if (r.len <= @max(id_col, title_col)) continue;
        if (state_col) |s| if (s < r.len and std.ascii.eqlIgnoreCase(r[s], "archived")) continue;
        const iid = iidOf(r[id_col]) orelse continue;
        const t = r[title_col];
        const named = t[0 .. std.mem.find(u8, t, ": ") orelse t.len];
        const item = graph.find(named) orelse graph.formerly(named) orelse {
            try unmatched.append(arena, t);
            continue;
        };
        try entries.append(arena, .{ .id = item.id, .iid = iid });
    }
    return .{ .entries = entries.items, .unmatched = unmatched.items };
}

fn column(header: []const []const u8, name: []const u8) ?usize {
    for (header, 0..) |h, i| if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, h, " "), name)) return i;
    return null;
}

/// `12` or `REQ-12`
fn iidOf(cell: []const u8) ?u64 {
    var s = std.mem.trim(u8, cell, " ");
    if (std.ascii.startsWithIgnoreCase(s, "REQ-")) s = s[4..];
    return std.fmt.parseInt(u64, s, 10) catch null;
}

/// The map kept in the project; empty when there is none
pub fn loadMap(io: Io, arena: std.mem.Allocator, root: Io.Dir) ![]const Entry {
    var out: std.ArrayList(Entry) = .empty;
    const text = root.readFileAlloc(io, map_file, arena, .limited(1 << 24)) catch return out.items;
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => return out.items,
    };
    for (table.keys()) |id| {
        const v = table.get(id) orelse continue;
        if (v == .integer and v.integer > 0) try out.append(arena, .{ .id = id, .iid = @intCast(v.integer) });
    }
    return out.items;
}

/// Writes the map, in the order of the IIDs
pub fn saveMap(io: Io, arena: std.mem.Allocator, root: Io.Dir, entries: []const Entry) !void {
    const sorted = try arena.dupe(Entry, entries);
    std.mem.sort(Entry, sorted, {}, byIid);
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(arena, "# The GitLab requirement of each item: written by skein import gitlab-requirements, committed.\n");
    for (sorted) |e| try text.print(arena, "{s} = {d}\n", .{ try write.string(arena, e.id), e.iid });
    try root.writeFile(io, .{ .sub_path = map_file, .data = text.items });
}

fn byIid(_: void, a: Entry, b: Entry) bool {
    return a.iid < b.iid;
}

/// The requirements report, `{"IID": "passed" | "failed"}`: an item fails
/// when a result of any implementation failed, passes when one passed and
/// none failed, and is left out when it is untested
pub fn report(arena: std.mem.Allocator, entries: []const Entry, results: *const Results, idx: *const Results.Index, graph: *const Graph) ![]const u8 {
    const sorted = try arena.dupe(Entry, entries);
    std.mem.sort(Entry, sorted, {}, byIid);
    const implementations = try results.implementations(arena);
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '{');
    var first = true;
    for (sorted) |e| {
        const item = graph.find(e.id) orelse graph.formerly(e.id) orelse continue;
        var passed = false;
        var failed = false;
        for (implementations) |impl| switch (results.verdict(idx, item.id, impl)) {
            .passed => passed = true,
            .failed => failed = true,
            .untested => {},
        };
        if (!passed and !failed) continue;
        try out.print(arena, "{s}\"{d}\":\"{s}\"", .{ if (first) "" else ",", e.iid, if (failed) "failed" else "passed" });
        first = false;
    }
    try out.appendSlice(arena, "}\n");
    return out.items;
}

test {
    _ = @import("_test/gitlab_requirements.zig");
}

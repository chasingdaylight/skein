//! The stored schedule: `.skein/schedule.toml`, which skein writes and the
//! project commits, the one source of the schedule offline; and, beside it
//! when the configuration asks (`[schedule] also`), the same as JSON and
//! CSV for tools that read those. skein reads only the TOML.

const std = @import("std");

const Json = @import("../output/Json.zig");
const Project = @import("../Project.zig");
const day = @import("day.zig");
const schedule = @import("schedule.zig");

const Error = std.mem.Allocator.Error;

pub const toml_file = Project.dir_name ++ "/schedule.toml";

/// The files of the formats `also` names, besides the TOML
pub fn fileOf(format: []const u8) []const u8 {
    return if (std.mem.eql(u8, format, "json")) Project.dir_name ++ "/schedule.json" else Project.dir_name ++ "/schedule.csv";
}

pub fn toml(arena: std.mem.Allocator, entries: []const schedule.Entry) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "# The schedule of the work items, written by 'skein schedule'; not to be\n# edited. 'skein check' reports when it is not the one the items give.\n");
    for (entries) |e| {
        try out.print(arena, "\n[items.\"{s}\"]\n", .{e.work.item.id});
        if (e.start) |s| try out.print(arena, "start = {s}\n", .{&day.format(s)});
        if (e.finish) |f| try out.print(arena, "finish = {s}\n", .{&day.format(f)});
        try out.print(arena, "mode = \"{t}\"\nsource = \"{t}\"\n", .{ e.mode, e.source });
        if (e.slack) |s| try out.print(arena, "slack = {d}\ncritical = {}\n", .{ s, e.critical() });
    }
    return out.items;
}

pub fn json(arena: std.mem.Allocator, entries: []const schedule.Entry) Error![]const u8 {
    var j: Json = .{ .arena = arena };
    try j.beginObject();
    try j.key("items");
    try j.beginArray();
    for (entries) |e| {
        try j.beginObject();
        try j.key("id");
        try j.string(e.work.item.id);
        try j.key("start");
        try j.optional(if (e.start) |s| try arena.dupe(u8, &day.format(s)) else null);
        try j.key("finish");
        try j.optional(if (e.finish) |f| try arena.dupe(u8, &day.format(f)) else null);
        try j.key("mode");
        try j.string(@tagName(e.mode));
        try j.key("source");
        try j.string(@tagName(e.source));
        if (e.slack) |s| {
            try j.key("slack");
            try j.integer(s);
            try j.key("critical");
            try j.boolean(e.critical());
        }
        try j.endObject();
    }
    try j.endArray();
    try j.endObject();
    return j.finish();
}

pub fn csv(arena: std.mem.Allocator, entries: []const schedule.Entry) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "id,start,finish,mode,source,slack,critical\n");
    for (entries) |e| {
        // IDs have no commas or quotes
        try out.print(arena, "{s},", .{e.work.item.id});
        if (e.start) |s| try out.appendSlice(arena, &day.format(s));
        try out.append(arena, ',');
        if (e.finish) |f| try out.appendSlice(arena, &day.format(f));
        try out.print(arena, ",{t},{t},", .{ e.mode, e.source });
        if (e.slack) |s| try out.print(arena, "{d},{}", .{ s, e.critical() }) else try out.append(arena, ',');
        try out.append(arena, '\n');
    }
    return out.items;
}

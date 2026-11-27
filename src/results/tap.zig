//! Results from TAP, the Test Anything Protocol: one line per test, `ok 1 -
//! name` or `not ok 2 - name`, with `# SKIP` or `# TODO` after it for one
//! that was skipped or is not expected to pass yet (both count as skipped).
//! Indented lines (subtests) are read too. TAP names no file, so a comment
//! `# file: PATH` gives the file of the tests after it, and a YAML block
//! after a test (`---` to `...`) may give its `file`, `item` and `items`.
//! Comments `# implementation: NAME` and `# version: V` apply to the whole
//! file. `Bail out!` is a failed result.

const std = @import("std");

const Record = @import("read.zig").Record;
const normalize = @import("junit.zig").normalize;
const yaml = @import("../import/doorstop/yaml.zig");

pub const Error = error{BadResults} || std.mem.Allocator.Error;

pub fn records(arena: std.mem.Allocator, text: []const u8, why: *[]const u8) Error![]const Record {
    var out: std.ArrayList(Record) = .empty;
    var file: ?[]const u8 = null;
    var implementation: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: u32 = 0;
    while (lines.next()) |raw| {
        n += 1;
        const line = std.mem.trim(u8, std.mem.trimEnd(u8, raw, "\r"), " \t");
        if (std.mem.startsWith(u8, line, "#")) {
            const comment = std.mem.trim(u8, line[1..], " \t");
            if (keyed(comment, "file")) |v| file = try normalize(arena, v);
            if (keyed(comment, "implementation")) |v| implementation = v;
            if (keyed(comment, "version")) |v| version = v;
            continue;
        }
        if (std.mem.startsWith(u8, line, "Bail out!")) {
            var r: Record = .{};
            try r.fields.put(arena, "test", "Bail out!");
            try r.fields.put(arena, "result", "fail");
            const reason = std.mem.trim(u8, line["Bail out!".len..], " \t");
            if (reason.len > 0) try r.fields.put(arena, "note", reason);
            try out.append(arena, r);
            continue;
        }
        if (std.mem.eql(u8, line, "---")) {
            if (out.items.len == 0) return bad(arena, why, n, "a YAML block before any test");
            try diagnostics(arena, &lines, &n, raw, &out.items[out.items.len - 1], why);
            continue;
        }
        const failed = std.mem.startsWith(u8, line, "not ok");
        if (!failed and !std.mem.startsWith(u8, line, "ok")) continue;
        var rest = line[if (failed) "not ok".len else "ok".len..];
        if (rest.len > 0 and rest[0] != ' ' and rest[0] != '\t' and rest[0] != '#') continue;
        rest = std.mem.trimStart(u8, rest, " \t");
        while (rest.len > 0 and std.ascii.isDigit(rest[0])) rest = rest[1..];
        rest = std.mem.trimStart(u8, rest, " \t");
        if (std.mem.startsWith(u8, rest, "-")) rest = std.mem.trimStart(u8, rest[1..], " \t");
        var r: Record = .{};
        var result: []const u8 = if (failed) "fail" else "pass";
        var name = rest;
        if (std.mem.findScalar(u8, rest, '#')) |hash| {
            name = std.mem.trimEnd(u8, rest[0..hash], " \t");
            const directive = std.mem.trim(u8, rest[hash + 1 ..], " \t");
            if (std.ascii.startsWithIgnoreCase(directive, "skip") or std.ascii.startsWithIgnoreCase(directive, "todo")) {
                result = "skip";
                const reason = std.mem.trim(u8, directive[4..], " \t:");
                if (reason.len > 0) try r.fields.put(arena, "note", reason);
            }
        }
        if (name.len > 0) try r.fields.put(arena, "test", name);
        try r.fields.put(arena, "result", result);
        if (file) |f| try r.fields.put(arena, "file", f);
        try out.append(arena, r);
    }
    for (out.items) |*r| {
        if (implementation) |v| if (r.get("implementation") == null) try r.fields.put(arena, "implementation", v);
        if (version) |v| if (r.get("version") == null) try r.fields.put(arena, "version", v);
    }
    return out.items;
}

/// The value of `key: value`, when `comment` is that
fn keyed(comment: []const u8, key: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, comment, key)) return null;
    const rest = comment[key.len..];
    if (rest.len == 0 or rest[0] != ':') return null;
    const v = std.mem.trim(u8, rest[1..], " \t");
    return if (v.len > 0) v else null;
}

/// The YAML block after a test, up to `...`, whose `file`, `item` and
/// `items` go to the test's result
fn diagnostics(arena: std.mem.Allocator, lines: *std.mem.SplitIterator(u8, .scalar), n: *u32, opening: []const u8, r: *Record, why: *[]const u8) Error!void {
    const indent = opening.len - std.mem.trimStart(u8, opening, " \t").len;
    var block: std.ArrayList(u8) = .empty;
    const start = n.*;
    while (lines.next()) |raw| {
        n.* += 1;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t"), "...")) break;
        try block.appendSlice(arena, if (line.len >= indent) line[indent..] else std.mem.trimStart(u8, line, " \t"));
        try block.append(arena, '\n');
    } else return bad(arena, why, start, "a YAML block without its closing '...'");
    var at: u32 = 0;
    const doc = yaml.parse(arena, block.items, &at) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedYaml => return bad(arena, why, start + at, "YAML that skein does not read"),
    };
    if (doc != .map) return;
    for ([_][]const u8{ "file", "item" }) |key| {
        const v = doc.get(key) orelse continue;
        if (v != .scalar) continue;
        try r.fields.put(arena, key, if (std.mem.eql(u8, key, "file")) try normalize(arena, v.scalar) else v.scalar);
    }
    if (doc.get("items")) |v| switch (v) {
        .list => |l| {
            var items: std.ArrayList([]const u8) = .empty;
            for (l) |s| if (s == .scalar) try items.append(arena, s.scalar);
            try r.lists.put(arena, "items", items.items);
        },
        .scalar => |s| try r.lists.put(arena, "items", try arena.dupe([]const u8, &.{s})),
        .map => {},
    };
}

fn bad(arena: std.mem.Allocator, why: *[]const u8, line: u32, message: []const u8) Error {
    why.* = try arena.print("{d}: {s}", .{ line, message });
    return error.BadResults;
}

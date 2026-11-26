//! Results from JUnit XML, which most CI systems and many test runners
//! write: a `testcase` per test, in `testsuite` elements (nested or under
//! `testsuites`). A test failed with a `failure` or `error` element and was
//! skipped with `skipped`. Its file is the `file` attribute of the test
//! case or of the nearest suite. `property` elements (`<properties>` of a
//! test case or a suite) may give `item`, `items`, `implementation` and
//! `version`; the nearest one counts.

const std = @import("std");

const Record = @import("read.zig").Record;
const xml = @import("../xml.zig");

pub const Error = error{BadResults} || std.mem.Allocator.Error;

pub fn records(arena: std.mem.Allocator, text: []const u8, why: *[]const u8) Error![]const Record {
    var diag: xml.Diagnostic = .{};
    const root = xml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidXml => {
            why.* = try arena.print("{d}:{d}: {s}", .{ diag.line, diag.column, diag.message });
            return error.BadResults;
        },
    };
    if (!root.is("testsuites") and !root.is("testsuite")) {
        why.* = "JUnit XML has 'testsuites' or 'testsuite' at its root";
        return error.BadResults;
    }
    var out: std.ArrayList(Record) = .empty;
    try suite(arena, root, &.{}, &out);
    return out.items;
}

/// What a suite passes down to what it holds: its file and properties
const Inherited = []const *const xml.Element;

fn suite(arena: std.mem.Allocator, e: *const xml.Element, outer: Inherited, out: *std.ArrayList(Record)) Error!void {
    const chain = try arena.alloc(*const xml.Element, outer.len + 1);
    @memcpy(chain[0..outer.len], outer);
    chain[outer.len] = e;
    for (e.content) |n| {
        const c = switch (n) {
            .element => |c| c,
            .text => continue,
        };
        if (c.is("testsuite")) try suite(arena, c, chain, out);
        if (c.is("testcase")) try out.append(arena, try case(arena, c, chain));
    }
}

fn case(arena: std.mem.Allocator, e: *const xml.Element, suites: Inherited) Error!Record {
    var r: Record = .{};
    if (e.attribute("name")) |name| try r.fields.put(arena, "test", name);
    const result: []const u8, const why = if (e.child("failure") orelse e.child("error")) |f|
        .{ "fail", f }
    else if (e.child("skipped")) |s| .{ "skip", s } else .{ "pass", null };
    try r.fields.put(arena, "result", result);
    if (why) |w| if (w.attribute("message")) |m| try r.fields.put(arena, "note", m);
    // the case's own, else the nearest suite's
    var file = e.attribute("file");
    var i = suites.len;
    while (file == null and i > 0) : (i -= 1) file = suites[i - 1].attribute("file");
    if (file) |f| try r.fields.put(arena, "file", try normalize(arena, f));
    for ([_][]const u8{ "item", "implementation", "version" }) |key| {
        if (try nearest(arena, e, suites, key)) |v| try r.fields.put(arena, key, v);
    }
    var items: std.ArrayList([]const u8) = .empty;
    for (try properties(arena, e, "items")) |v| {
        var it = std.mem.tokenizeAny(u8, v, ", ");
        while (it.next()) |id| try items.append(arena, id);
    }
    if (items.items.len > 0) try r.lists.put(arena, "items", items.items);
    return r;
}

/// The property `key` of the case, else of the nearest suite that has it
fn nearest(arena: std.mem.Allocator, e: *const xml.Element, suites: Inherited, key: []const u8) Error!?[]const u8 {
    if ((try properties(arena, e, key)).len > 0) return (try properties(arena, e, key))[0];
    var i = suites.len;
    while (i > 0) : (i -= 1) {
        const found = try properties(arena, suites[i - 1], key);
        if (found.len > 0) return found[0];
    }
    return null;
}

/// The values of the properties `key` of `e`: `value`, else the text
fn properties(arena: std.mem.Allocator, e: *const xml.Element, key: []const u8) Error![]const []const u8 {
    const props = e.child("properties") orelse return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    for (try props.children(arena, "property")) |p| {
        const name = p.attribute("name") orelse continue;
        if (!std.mem.eql(u8, name, key)) continue;
        try out.append(arena, p.attribute("value") orelse std.mem.trim(u8, try p.text(arena), " \t\r\n"));
    }
    return out.items;
}

/// A file as the project names it: forward slashes, without a leading `./`
pub fn normalize(arena: std.mem.Allocator, path: []const u8) Error![]const u8 {
    var p = path;
    if (std.mem.findScalar(u8, p, '\\') != null) {
        const copy = try arena.dupe(u8, p);
        std.mem.replaceScalar(u8, copy, '\\', '/');
        p = copy;
    }
    while (std.mem.startsWith(u8, p, "./")) p = p[2..];
    return p;
}

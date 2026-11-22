//! Test results, and what they say of the items. They come from the
//! results files the project keeps (`[results] paths`) and the ones a
//! command is given (`--results FILE`). A result belongs to items:
//!
//! - by the file of its test (`file`): the items cited in that file;
//! - by an item it names (`item`), such as a procedure of a test plan run
//!   by a person: that item, and the items its links point to;
//! - by the items it names (`items`).
//!
//! Per implementation, an item passes when every result that belongs to it
//! passed, fails when one failed, and is untested when none belongs to it
//! or all were skipped.

const std = @import("std");
const Io = std.Io;

const Graph = @import("../graph/Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const files = @import("../files.zig");
const read = @import("read.zig");

const Results = @This();

all: []const Result = &.{},

pub const Outcome = enum { pass, fail, skip };

pub const Result = struct {
    /// the test's name
    name: ?[]const u8 = null,
    /// the file of the test, from the project's root
    file: ?[]const u8 = null,
    /// an item it is the result of: a procedure, say
    item: ?[]const u8 = null,
    /// items it names directly
    items: []const []const u8 = &.{},
    outcome: Outcome,
    /// "" when the result names none
    implementation: []const u8 = "",
    version: ?[]const u8 = null,
    note: ?[]const u8 = null,
    /// the results file it is in, and its place there (1-based)
    source: []const u8,
    index: usize,

    /// The test's name, or its file, or what it is of, for a list
    pub fn label(self: *const Result) []const u8 {
        return self.name orelse self.file orelse self.item orelse "a result";
    }
};

pub const extensions = [_][]const u8{ ".toml", ".json", ".yaml", ".yml" };

/// The results of the project's results paths, and of the files `extra`
/// (paths from the current directory). Files that cannot be read, and
/// results that are not well formed, are reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, extra: []const []const u8, report: *Report) !Results {
    var out: std.ArrayList(Result) = .empty;
    for (project.results) |path| {
        const found = if (read.formatOf(path) != null) &.{path} else files.list(io, arena, root, path, &extensions) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(Project.config_file, 0, 0, "results: cannot read '{s}' ({s})", .{ path, @errorName(e) });
                continue;
            },
        };
        for (found) |file| try readFile(io, arena, root, file, &out, report);
    }
    for (extra) |file| try readFile(io, arena, Io.Dir.cwd(), file, &out, report);
    return .{ .all = out.items };
}

fn readFile(io: Io, arena: std.mem.Allocator, dir: Io.Dir, file: []const u8, out: *std.ArrayList(Result), report: *Report) !void {
    const format = read.formatOf(file) orelse return report.add(file, 0, 0, "a results file is .toml, .json, .yaml or .yml", .{});
    const text = dir.readFileAlloc(io, file, arena, .limited(1 << 26)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return report.add(file, 0, 0, "cannot read the file ({s})", .{@errorName(e)}),
    };
    var why: []const u8 = "";
    const records = read.records(arena, format, text, &why) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return report.add(file, 0, 0, "{s}", .{why}),
    };
    for (records, 1..) |*r, n| {
        const given = r.get("result") orelse {
            try report.add(file, 0, 0, "result {d}: it says nothing of how it went ('result' = pass, fail or skip)", .{n});
            continue;
        };
        const outcome = std.meta.stringToEnum(Outcome, given) orelse {
            try report.add(file, 0, 0, "result {d}: '{s}' is not pass, fail or skip", .{ n, given });
            continue;
        };
        try out.append(arena, .{
            .name = r.get("test"),
            .file = r.get("file"),
            .item = r.get("item"),
            .items = r.items,
            .outcome = outcome,
            .implementation = r.get("implementation") orelse "",
            .version = r.get("version"),
            .note = r.get("note"),
            .source = file,
            .index = n,
        });
    }
}

/// Which results belong to which items
pub const Index = struct {
    /// by item ID: the results that belong to it, by their place in `all`
    by_item: std.array_hash_map.String(std.ArrayList(usize)) = .empty,
    /// the results that belong to no item
    unmatched: []const usize = &.{},
};

pub fn index(self: *const Results, arena: std.mem.Allocator, graph: *const Graph, citations: *const Graph.Citations) !Index {
    var out: Index = .{};
    var unmatched: std.ArrayList(usize) = .empty;
    for (self.all, 0..) |r, i| {
        var targets: std.ArrayList([]const u8) = .empty;
        try targets.appendSlice(arena, r.items);
        if (r.item) |id| if (graph.find(id) orelse graph.formerly(id)) |item| {
            try targets.append(arena, item.id);
            for (item.links) |l| try targets.append(arena, l.target);
        };
        if (r.file) |file| for (citations.all) |c| {
            if (std.mem.eql(u8, c.file, file)) try targets.append(arena, c.target);
        };
        var matched = false;
        for (targets.items) |t| {
            const item = graph.find(t) orelse graph.formerly(t) orelse continue;
            const entry = try out.by_item.getOrPut(arena, item.id);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            if (std.mem.findScalar(usize, entry.value_ptr.items, i) == null) try entry.value_ptr.append(arena, i);
            matched = true;
        }
        if (!matched) try unmatched.append(arena, i);
    }
    out.unmatched = unmatched.items;
    return out;
}

pub const Verdict = enum { passed, failed, untested };

/// What the results of `implementation` say of the item `id`
pub fn verdict(self: *const Results, idx: *const Index, id: []const u8, implementation: []const u8) Verdict {
    const list = idx.by_item.get(id) orelse return .untested;
    var passed = false;
    for (list.items) |i| {
        const r = self.all[i];
        if (!std.mem.eql(u8, r.implementation, implementation)) continue;
        switch (r.outcome) {
            .fail => return .failed,
            .pass => passed = true,
            .skip => {},
        }
    }
    return if (passed) .passed else .untested;
}

/// The implementations the results name, in order; "" for results that
/// name none
pub fn implementations(self: *const Results, arena: std.mem.Allocator) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (self.all) |r| {
        for (out.items) |have| {
            if (std.mem.eql(u8, have, r.implementation)) break;
        } else try out.append(arena, r.implementation);
    }
    std.mem.sort([]const u8, out.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return out.items;
}

/// "cesium0 0.3.1", or "results that name no implementation"
pub fn implementationName(self: *const Results, arena: std.mem.Allocator, implementation: []const u8) ![]const u8 {
    if (implementation.len == 0) return "results that name no implementation";
    for (self.all) |r| {
        if (!std.mem.eql(u8, r.implementation, implementation)) continue;
        if (r.version) |v| return arena.print("{s} {s}", .{ implementation, v });
    }
    return implementation;
}

test {
    _ = read;
    _ = @import("_test/results.zig");
}

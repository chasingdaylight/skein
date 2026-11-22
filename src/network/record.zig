//! `.skein/network.toml`: the recorded state of the network. For each
//! other repository the project declares, the commit its items were last
//! checked against, with the fingerprint of its items and the identity it
//! declares; and the repositories reached only through those, each once,
//! at the commit their records give. `skein pin` writes it; it is not
//! edited by hand. A submodule is recorded by git instead.

const std = @import("std");
const Io = std.Io;

const Report = @import("../Report.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const file = ".skein/network.toml";

/// One declared repository's recorded state
pub const Entry = struct {
    /// the short name the project gives it
    name: []const u8,
    commit: []const u8,
    /// of its items at that commit, in hexadecimal
    fingerprint: []const u8,
    /// what it calls itself (`[project] id`); null when it declares none
    id: ?[]const u8 = null,
};

/// A repository reached through the declared ones, by its identity
pub const Reached = struct {
    id: []const u8,
    commit: []const u8,
    /// the declared repositories whose records name it
    through: []const []const u8,
};

pub const Record = struct {
    entries: []const Entry = &.{},
    reached: []const Reached = &.{},
};

/// The record of `root`; empty when there is none. A record that cannot
/// be read is reported.
pub fn read(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!Record {
    const source = root.readFileAlloc(io, file, arena, .limited(1 << 24)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return .{},
        else => {
            try report.add(file, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
            return .{};
        },
    };
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, source, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(file, diag.line, diag.column, "{s}", .{diag.message});
            return .{};
        },
    };
    var out: Record = .{};
    if (table.get("repositories")) |repositories| {
        if (repositories != .table) return malformed(report);
        var entries: std.ArrayList(Entry) = .empty;
        for (repositories.table.keys()) |name| {
            const t = repositories.table.get(name).?;
            if (t != .table) return malformed(report);
            const commit = string(t.table, "commit") orelse return malformed(report);
            const fp = string(t.table, "fingerprint") orelse return malformed(report);
            try entries.append(arena, .{ .name = name, .commit = commit, .fingerprint = fp, .id = string(t.table, "id") });
        }
        out.entries = entries.items;
    }
    if (table.get("reached")) |reached| {
        if (reached != .table) return malformed(report);
        var list: std.ArrayList(Reached) = .empty;
        for (reached.table.keys()) |id| {
            const t = reached.table.get(id).?;
            if (t != .table) return malformed(report);
            const commit = string(t.table, "commit") orelse return malformed(report);
            var through: std.ArrayList([]const u8) = .empty;
            if (t.table.get("through")) |names| {
                if (names != .array) return malformed(report);
                for (names.array.values()) |n| {
                    if (n != .string) return malformed(report);
                    try through.append(arena, n.string);
                }
            }
            try list.append(arena, .{ .id = id, .commit = commit, .through = through.items });
        }
        out.reached = list.items;
    }
    return out;
}

fn string(table: *const toml.Table, key: []const u8) ?[]const u8 {
    const v = table.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn malformed(report: *Report) std.mem.Allocator.Error!Record {
    try report.add(file, 0, 0, "this is not a record that 'skein pin' writes; write it again with 'skein pin'", .{});
    return .{};
}

/// The entry of `name` in `entries`
pub fn find(entries: []const Entry, name: []const u8) ?Entry {
    for (entries) |e| {
        if (std.mem.eql(u8, e.name, name)) return e;
    }
    return null;
}

/// The text of `record`, in order of name and identity
pub fn render(arena: std.mem.Allocator, record: Record) std.mem.Allocator.Error![]const u8 {
    const entries = try arena.dupe(Entry, record.entries);
    std.mem.sort(Entry, entries, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    const reached = try arena.dupe(Reached, record.reached);
    std.mem.sort(Reached, reached, {}, struct {
        fn lt(_: void, a: Reached, b: Reached) bool {
            return std.mem.lessThan(u8, a.id, b.id);
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena,
        \\# The state of the network: the commit of each other repository that
        \\# the items were last checked against. Written by `skein pin`; not
        \\# edited by hand.
        \\
    );
    for (entries) |e| {
        try out.print(arena, "\n[repositories.{s}]\n", .{e.name});
        if (e.id) |id| try out.print(arena, "id = {s}\n", .{try write.string(arena, id)});
        try out.print(arena, "commit = {s}\nfingerprint = {s}\n", .{ try write.string(arena, e.commit), try write.string(arena, e.fingerprint) });
    }
    for (reached) |r| {
        try out.print(arena, "\n[reached.{s}]\ncommit = {s}\nthrough = {s}\n", .{ try write.string(arena, r.id), try write.string(arena, r.commit), try write.strings(arena, r.through) });
    }
    return out.items;
}

test "a record reads back as it was written" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, ".skein");
    const record: Record = .{
        .entries = &.{
            .{ .name = "website", .commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", .fingerprint = "2222222222222222222222222222222222222222222222222222222222222222" },
            .{ .name = "compiler", .commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .fingerprint = "1111111111111111111111111111111111111111111111111111111111111111", .id = "example/compiler" },
        },
        .reached = &.{.{ .id = "example/grammar", .commit = "cccccccccccccccccccccccccccccccccccccccc", .through = &.{"website"} }},
    };
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = file, .data = try render(a, record) });
    var report: Report = .{ .arena = a };
    const back = try read(std.testing.io, a, tmp.dir, &report);
    try std.testing.expect(report.ok());
    try std.testing.expectEqual(2, back.entries.len);
    try std.testing.expectEqualStrings("compiler", back.entries[0].name);
    try std.testing.expectEqualStrings("example/compiler", find(back.entries, "compiler").?.id.?);
    try std.testing.expectEqual(null, find(back.entries, "website").?.id);
    try std.testing.expectEqualStrings("2222222222222222222222222222222222222222222222222222222222222222", find(back.entries, "website").?.fingerprint);
    try std.testing.expectEqualStrings("example/grammar", back.reached[0].id);
    try std.testing.expectEqualStrings("website", back.reached[0].through[0]);
}

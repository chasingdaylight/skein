//! `.skein/network.toml`: the recorded state of the network, the commit
//! of each other repository the project's items were last checked
//! against, with the fingerprint of its items. `skein pin` writes it;
//! it is not edited by hand.

const std = @import("std");
const Io = std.Io;

const Report = @import("../Report.zig");
const toml = @import("../toml.zig");
const write = @import("../toml/write.zig");

pub const file = ".skein/network.toml";

/// One repository's recorded state
pub const Entry = struct {
    /// the short name the project gives it
    name: []const u8,
    commit: []const u8,
    /// of its items at that commit, in hexadecimal
    fingerprint: []const u8,
};

/// The entries of `root`'s record, by name; none when there is no record.
/// A record that cannot be read is reported.
pub fn read(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error![]const Entry {
    const source = root.readFileAlloc(io, file, arena, .limited(1 << 24)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return &.{},
        else => {
            try report.add(file, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
            return &.{};
        },
    };
    var diag: toml.Diagnostic = .{};
    const table = toml.parse(arena, source, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(file, diag.line, diag.column, "{s}", .{diag.message});
            return &.{};
        },
    };
    const repositories = table.get("repositories") orelse return &.{};
    if (repositories != .table) return malformed(report);
    var out: std.ArrayList(Entry) = .empty;
    for (repositories.table.keys()) |name| {
        const entry = repositories.table.get(name).?;
        if (entry != .table) return malformed(report);
        const commit = entry.table.get("commit") orelse return malformed(report);
        const fp = entry.table.get("fingerprint") orelse return malformed(report);
        if (commit != .string or fp != .string) return malformed(report);
        try out.append(arena, .{ .name = name, .commit = commit.string, .fingerprint = fp.string });
    }
    return out.items;
}

fn malformed(report: *Report) std.mem.Allocator.Error![]const Entry {
    try report.add(file, 0, 0, "this is not a record that 'skein pin' writes; write it again with 'skein pin'", .{});
    return &.{};
}

/// The entry of `name` in `entries`
pub fn find(entries: []const Entry, name: []const u8) ?Entry {
    for (entries) |e| {
        if (std.mem.eql(u8, e.name, name)) return e;
    }
    return null;
}

/// The text of a record of `entries`, in order of name
pub fn render(arena: std.mem.Allocator, entries: []const Entry) std.mem.Allocator.Error![]const u8 {
    const sorted = try arena.dupe(Entry, entries);
    std.mem.sort(Entry, sorted, {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena,
        \\# The state of the network: the commit of each other repository that
        \\# the items were last checked against. Written by `skein pin`; not
        \\# edited by hand.
        \\
    );
    for (sorted) |e| {
        try out.print(arena, "\n[repositories.{s}]\ncommit = {s}\nfingerprint = {s}\n", .{ e.name, try write.string(arena, e.commit), try write.string(arena, e.fingerprint) });
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
    const entries = [_]Entry{
        .{ .name = "website", .commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", .fingerprint = "2222222222222222222222222222222222222222222222222222222222222222" },
        .{ .name = "compiler", .commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .fingerprint = "1111111111111111111111111111111111111111111111111111111111111111" },
    };
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = file, .data = try render(a, &entries) });
    var report: Report = .{ .arena = a };
    const back = try read(std.testing.io, a, tmp.dir, &report);
    try std.testing.expect(report.ok());
    try std.testing.expectEqual(2, back.len);
    try std.testing.expectEqualStrings("compiler", back[0].name);
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", find(back, "compiler").?.commit);
    try std.testing.expectEqualStrings("2222222222222222222222222222222222222222222222222222222222222222", find(back, "website").?.fingerprint);
}

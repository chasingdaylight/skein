//! The files skein keeps its records in, under `.skein/`: one per
//! document or directory of item files, TOML, one sorted line per record,
//! so that two branches conflict only where both touched the same
//! document. skein writes them; no one edits them by hand.

const std = @import("std");
const Io = std.Io;

const Item = @import("Item.zig");
const Report = @import("../Report.zig");
const toml = @import("../toml.zig");

pub const File = struct {
    /// from the project's root, with forward slashes
    path: []const u8,
    table: *const toml.Table,
};

/// The file under `dir` that holds the records of `item`: named after its
/// document, or after the directory of its item file
pub fn fileOf(arena: std.mem.Allocator, dir: []const u8, item: *const Item) std.mem.Allocator.Error![]const u8 {
    const subject = if (item.in_document) item.file else Io.Dir.path.dirnamePosix(item.file) orelse "_";
    return arena.print("{s}/{s}.toml", .{ dir, subject });
}

/// Reads every record file under `dir`. Files that cannot be read or are
/// no TOML are reported and left out.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, dir: []const u8, report: *Report) std.mem.Allocator.Error![]const File {
    var out: std.ArrayList(File) = .empty;
    var d = root.openDir(io, dir, .{ .iterate = true }) catch return out.items;
    defer d.close(io);
    var walker = try d.walk(arena);
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".toml")) continue;
        const path = try arena.print("{s}/{s}", .{ dir, entry.path });
        std.mem.replaceScalar(u8, path, '\\', '/');
        const text = d.readFileAlloc(io, entry.path, arena, .limited(1 << 26)) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(path, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
                continue;
            },
        };
        var diag: toml.Diagnostic = .{};
        const table = toml.parse(arena, text, &diag) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidToml => {
                try report.add(path, diag.line, diag.column, "{s}", .{diag.message});
                continue;
            },
        };
        try out.append(arena, .{ .path = path, .table = table });
    }
    // the order a directory lists its files in must not matter
    std.mem.sort(File, out.items, {}, struct {
        fn lt(_: void, a: File, b: File) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lt);
    return out.items;
}

/// Writes `file` with `header` (a comment line) and `lines` (each with
/// its line end), sorted, each once. With no lines the file is deleted.
pub fn write(io: Io, arena: std.mem.Allocator, root: Io.Dir, file: []const u8, header: []const u8, lines: [][]const u8) !void {
    if (lines.len == 0) {
        root.deleteFile(io, file) catch {};
        return;
    }
    std.mem.sort([]const u8, lines, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(arena, header);
    for (lines, 0..) |line, i| {
        if (i > 0 and std.mem.eql(u8, line, lines[i - 1])) continue;
        try text.appendSlice(arena, line);
    }
    if (Io.Dir.path.dirnamePosix(file)) |parent| try root.createDirPath(io, parent);
    try root.writeFile(io, .{ .sub_path = file, .data = text.items });
}

/// `s` as the inside of a TOML basic string
pub fn escape(arena: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.findAny(u8, s, "\"\\") == null) return s;
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (c == '"' or c == '\\') try out.append(arena, '\\');
        try out.append(arena, c);
    }
    return out.items;
}

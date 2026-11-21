//! A project: what its `.skein/` directory says. The files:
//!
//! - `.skein/config.toml`: the project's name and where its items are
//! - `.skein/types/<name>.toml`: one item type each
//! - `.skein/links/<name>.toml`: one link type each
//! - `.skein/profiles/<name>.toml`: one profile each

const std = @import("std");
const Io = std.Io;

const Report = @import("Report.zig");
const Schema = @import("schema/Schema.zig");
const toml = @import("toml.zig");

const Project = @This();

pub const dir_name = ".skein";
pub const config_file = dir_name ++ "/config.toml";

name: []const u8 = "",
sources: []const Source = &.{},
schema: Schema = .{},

/// A place in the repository that holds items
pub const Source = struct {
    /// from the project's root, with forward slashes
    path: []const u8,
    kind: Kind,
    /// items: the type of an item that names none
    item_type: ?[]const u8 = null,

    pub const Kind = enum {
        /// Markdown documents whose paragraphs can be items
        documents,
        /// Markdown files that are one item each
        items,
    };
};

/// What `root`'s `.skein/` declares. Everything is allocated in `arena`.
/// Mistakes go to `report`, and what could be read is still returned.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, report: *Report) std.mem.Allocator.Error!Project {
    var out: Project = .{};
    if (try readToml(io, arena, root, config_file, report)) |table| {
        try out.readConfig(.{ .report = report, .arena = arena, .file = config_file, .table = table });
    }
    out.schema = .{
        .types = try loadEach(Schema.ItemType, io, arena, root, "types", report),
        .links = try loadEach(Schema.LinkType, io, arena, root, "links", report),
        .profiles = try loadEach(Schema.Profile, io, arena, root, "profiles", report),
    };
    try out.schema.validate(report, dir_name);
    for (out.sources) |s| {
        const t = s.item_type orelse continue;
        if (out.schema.itemType(t) == null) try report.add(config_file, 0, 0, "sources: there is no item type '{s}'", .{t});
    }
    return out;
}

fn readConfig(self: *Project, r: Schema.Reader) Schema.Reader.Error!void {
    try r.known(&.{ "project", "sources" });
    if (try r.child("project")) |project| {
        try project.known(&.{"name"});
        self.name = try project.string("name") orelse "";
    }
    var sources: std.ArrayList(Source) = .empty;
    for (try r.children("sources")) |s| {
        try s.known(&.{ "path", "kind", "type" });
        const path = try s.string("path") orelse {
            try s.complain("path", "a source needs a path", .{});
            continue;
        };
        const kind_name = try s.string("kind") orelse "documents";
        const kind = std.meta.stringToEnum(Source.Kind, kind_name) orelse {
            try s.complain("kind", "expected \"documents\" or \"items\"", .{});
            continue;
        };
        if (std.Io.Dir.path.isAbsolute(path) or std.mem.find(u8, path, "..") != null or std.mem.findScalar(u8, path, '\\') != null) {
            try s.complain("path", "a path is written from the project's root, with forward slashes", .{});
            continue;
        }
        try sources.append(r.arena, .{
            .path = std.mem.trimEnd(u8, path, "/"),
            .kind = kind,
            .item_type = try s.string("type"),
        });
    }
    self.sources = sources.items;
}

/// The things declared by the TOML files of `.skein/<sub>/`, by name
fn loadEach(
    comptime T: type,
    io: Io,
    arena: std.mem.Allocator,
    root: Io.Dir,
    comptime sub: []const u8,
    report: *Report,
) std.mem.Allocator.Error![]const T {
    const dir_path = dir_name ++ "/" ++ sub;
    var dir = root.openDir(io, dir_path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var files: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".toml")) continue;
        try files.append(arena, try arena.dupe(u8, entry.name));
    }
    // the same order everywhere
    std.mem.sort([]const u8, files.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var out: std.ArrayList(T) = .empty;
    for (files.items) |file| {
        const path = try arena.print("{s}/{s}", .{ dir_path, file });
        const name = file[0 .. file.len - ".toml".len];
        if (!Schema.names.valid(name)) {
            try report.add(path, 0, 0, "the file's name is the name it declares: {s}", .{Schema.names.rule});
            continue;
        }
        const table = try readToml(io, arena, root, path, report) orelse continue;
        try out.append(arena, try T.read(.{ .report = report, .arena = arena, .file = path, .table = table }, name));
    }
    return out.items;
}

/// The root table of the TOML file at `path`; null, with the reason
/// reported, when it cannot be read
fn readToml(io: Io, arena: std.mem.Allocator, root: Io.Dir, path: []const u8, report: *Report) std.mem.Allocator.Error!?*toml.Table {
    const text = root.readFileAlloc(io, path, arena, .limited(1 << 24)) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try report.add(path, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
            return null;
        },
    };
    var diag: toml.Diagnostic = .{};
    return toml.parse(arena, text, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidToml => {
            try report.add(path, diag.line, diag.column, "{s}", .{diag.message});
            return null;
        },
    };
}

/// The nearest directory at or above `start` (a path) that has a
/// `.skein/`; null when none has
pub fn findRoot(io: Io, arena: std.mem.Allocator, start: []const u8) !?[]const u8 {
    var at: []const u8 = try Io.Dir.cwd().realPathFileAlloc(io, start, arena);
    while (true) {
        const candidate = try Io.Dir.path.join(arena, &.{ at, dir_name });
        if (Io.Dir.cwd().access(io, candidate, .{})) |_| return at else |_| {}
        at = Io.Dir.path.dirname(at) orelse return null;
    }
}

test {
    _ = @import("_test/project.zig");
}

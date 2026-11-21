//! Citations: where code and tests name the items they implement or
//! check. A citation is a comment such as `// spec: lex.comment.line`,
//! found by the marker its citation set (`[[citations]]` in
//! `.skein/config.toml`) gives; or a line of a `.skein-cites` file, which
//! cites items for every file of its directory and the ones below.

const std = @import("std");
const Io = std.Io;

const Graph = @import("Graph.zig");
const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Schema = @import("../schema/Schema.zig");
const files = @import("../files.zig");

const Citations = @This();

pub const directory_file = ".skein-cites";

/// in the order of the citation sets, the files and the lines
all: []const Citation = &.{},

pub const Citation = struct {
    /// the name of its citation set
    set: []const u8,
    target: []const u8,
    /// from the project's root, with forward slashes
    file: []const u8,
    line: u32,
    column: u32,
};

/// Reads the citations of every citation set of `project`. Files and
/// directories that cannot be read are reported.
pub fn load(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, report: *Report) std.mem.Allocator.Error!Citations {
    var out: std.ArrayList(Citation) = .empty;
    for (project.citations) |set| {
        // the directory files too, which are found by their name
        var suffixes: std.ArrayList([]const u8) = .empty;
        try suffixes.appendSlice(arena, set.files);
        try suffixes.append(arena, directory_file);
        const paths = files.list(io, arena, root, set.path, suffixes.items) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.add(Project.config_file, 0, 0, "citations: cannot read the directory '{s}' ({s})", .{ set.path, @errorName(e) });
                continue;
            },
        };
        for (paths) |path| {
            const text = root.readFileAlloc(io, path, arena, .limited(1 << 26)) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    try report.add(path, 0, 0, "cannot read the file ({s})", .{@errorName(e)});
                    continue;
                },
            };
            if (std.mem.endsWith(u8, path, directory_file)) {
                // it speaks for the set's files beside and below it; where
                // there are none, it belongs to another set
                if (coversAny(path, paths)) try readDirectoryFile(arena, set.name, path, text, &out);
            } else try readSource(arena, set, path, text, &out);
        }
    }
    return .{ .all = out.items };
}

/// Whether one of `paths` is a source file in the directory of the
/// directory file `path`, or below it
fn coversAny(path: []const u8, paths: []const []const u8) bool {
    const dir = path[0 .. path.len - directory_file.len];
    for (paths) |other| {
        if (std.mem.startsWith(u8, other, dir) and !std.mem.endsWith(u8, other, directory_file)) return true;
    }
    return false;
}

/// The citations in the source file `text`: on each line, the IDs after
/// the set's marker
pub fn readSource(arena: std.mem.Allocator, set: Project.CitationSet, file: []const u8, text: []const u8, out: *std.ArrayList(Citation)) std.mem.Allocator.Error!void {
    var line_no: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        line_no += 1;
        const at = std.mem.find(u8, line, set.marker) orelse continue;
        try readIds(arena, set.name, file, line, at + set.marker.len, line_no, out);
    }
}

/// The citations of a `.skein-cites` file: IDs, one or several on a
/// line; `#` starts a comment
pub fn readDirectoryFile(arena: std.mem.Allocator, set: []const u8, file: []const u8, text: []const u8, out: *std.ArrayList(Citation)) std.mem.Allocator.Error!void {
    var line_no: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        line_no += 1;
        const line = if (std.mem.findScalar(u8, raw, '#')) |hash| raw[0..hash] else raw;
        try readIds(arena, set, file, line, 0, line_no, out);
    }
}

/// The IDs of `line` from `start`: separated by commas or spaces, up to
/// the first word that is no ID. A full stop or the like after an ID is
/// not part of it ("Implements SRS-012.").
fn readIds(arena: std.mem.Allocator, set: []const u8, file: []const u8, line: []const u8, start: usize, line_no: u32, out: *std.ArrayList(Citation)) !void {
    var at = start;
    while (true) {
        while (at < line.len and isSeparator(line[at])) at += 1;
        const from = at;
        while (at < line.len and isIdChar(line[at])) at += 1;
        const word = line[from..at];
        // a word with anything else in it is no ID: the citation ends there
        if (word.len == 0 or (at < line.len and !isSeparator(line[at]))) return;
        const id = std.mem.trimEnd(u8, word, ".:-");
        if (id.len == 0) return;
        try out.append(arena, .{ .set = set, .target = id, .file = file, .line = line_no, .column = @intCast(from + 1) });
        // punctuation after an ID ends the sentence, and the citation
        if (id.len != word.len) return;
    }
}

fn isSeparator(c: u8) bool {
    return c == ' ' or c == '\t' or c == ',' or c == '\r';
}

fn isIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '-' or c == '_' or c == ':';
}

/// Reports the citations of items that do not exist, are removed, or are
/// of a type their citation set does not cite.
pub fn check(self: *const Citations, project: *const Project, graph: *const Graph, report: *Report) std.mem.Allocator.Error!void {
    for (self.all) |c| {
        // an item of another repository; checked once repositories are linked
        if (std.mem.findScalar(u8, c.target, ':') != null) continue;
        const target = graph.find(c.target) orelse {
            try report.add(c.file, c.line, c.column, "the citation names '{s}', and there is no such item", .{c.target});
            continue;
        };
        const set = project.citationSet(c.set).?;
        if (set.to.len > 0 and !Schema.names.contains(set.to, target.type_name)) {
            try report.add(c.file, c.line, c.column, "the citation names '{s}', a '{s}', which '{s}' citations do not cite", .{ c.target, target.type_name, set.name });
        }
        const target_type = project.schema.itemType(target.type_name) orelse continue;
        if (target.isTombstone(target_type)) try report.add(c.file, c.line, c.column, "the citation names '{s}', which is removed", .{c.target});
    }
}

/// The citations of `id`, in order
pub fn of(self: *const Citations, arena: std.mem.Allocator, id: []const u8) std.mem.Allocator.Error![]const Citation {
    var out: std.ArrayList(Citation) = .empty;
    for (self.all) |c| {
        if (std.mem.eql(u8, c.target, id)) try out.append(arena, c);
    }
    return out.items;
}

test {
    _ = @import("_test/citations.zig");
}

//! A template's standards (`project/standards/NAME/` in it), provided by
//! Skein rather than copied into the project (#263): for each template the
//! project names, its standards are written where they stand
//! (`standards/NAME/`), with a `.gitignore` there that keeps them out of the
//! repository, and read as read-only sources. They are written again only
//! when Skein's text differs, as after an upgrade. A project whose
//! configuration names such a source itself keeps its own copy, and `check`
//! says when that copy is the template's text unchanged, so it can go.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Template = @import("Template.zig");

const prefix = "project/";
const ignore = "# Written by skein from a template it carries, and kept out of git: skein provides this standard.\n*\n";

pub fn provide(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *Project, report: *Report) std.mem.Allocator.Error!void {
    var sources: std.ArrayList(Project.Source) = .empty;
    try sources.appendSlice(arena, project.sources);
    for (project.templates) |use| {
        const files = try Template.filesOf(arena, use.name, prefix ++ "standards/");
        var dirs: std.ArrayList([]const u8) = .empty;
        for (files) |f| {
            const dir = dirOf(f.path[prefix.len..]);
            for (dirs.items) |d| {
                if (std.mem.eql(u8, d, dir)) break;
            } else try dirs.append(arena, dir);
        }
        for (dirs.items) |dir| {
            const own = for (project.sources) |s| {
                if (std.mem.eql(u8, s.path, dir)) break true;
            } else false;
            if (own) {
                if (try unchanged(io, arena, root, files, dir)) try report.warn(Project.config_file, 0, 0, "{s} is the template {s}'s own text, unchanged: skein provides it, so the directory and its [[sources]] can go", .{ dir, use.name });
                continue;
            }
            if (!try write(io, arena, root, files, dir)) {
                try report.warn(Project.config_file, 0, 0, "the standards of the template {s} could not be written to {s}", .{ use.name, dir });
                continue;
            }
            try sources.append(arena, .{ .path = dir, .kind = .documents, .read_only = true });
        }
    }
    project.sources = sources.items;
}

/// Writes the standards of the template `name` where they stand, as
/// `provide` does, for `skein init`, which writes the project before its
/// options are given; false when one could not be written
pub fn writeFor(io: Io, arena: std.mem.Allocator, root: Io.Dir, name: []const u8) std.mem.Allocator.Error!bool {
    const files = try Template.filesOf(arena, name, prefix ++ "standards/");
    var ok = true;
    for (files) |f| {
        const dir = dirOf(f.path[prefix.len..]);
        if (!try write(io, arena, root, files, dir)) ok = false;
    }
    return ok;
}

/// `standards/NAME` of `standards/NAME/file.md`
fn dirOf(path: []const u8) []const u8 {
    const first = std.mem.findScalar(u8, path, '/') orelse return path;
    const second = std.mem.findScalarPos(u8, path, first + 1, '/') orelse return path;
    return path[0..second];
}

fn inDir(path: []const u8, dir: []const u8) bool {
    return path.len > dir.len and std.mem.startsWith(u8, path, dir) and path[dir.len] == '/';
}

/// Whether every file of the template under `dir` is in the project as it is
fn unchanged(io: Io, arena: std.mem.Allocator, root: Io.Dir, files: []const Template.File, dir: []const u8) std.mem.Allocator.Error!bool {
    for (files) |f| {
        const path = f.path[prefix.len..];
        if (!inDir(path, dir)) continue;
        const have = root.readFileAlloc(io, path, arena, .limited(1 << 28)) catch return false;
        if (!std.mem.eql(u8, have, f.data)) return false;
    }
    return true;
}

/// Writes what differs; false when it cannot
fn write(io: Io, arena: std.mem.Allocator, root: Io.Dir, files: []const Template.File, dir: []const u8) std.mem.Allocator.Error!bool {
    if (!try same(io, arena, root, try arena.print("{s}/.gitignore", .{dir}), ignore)) {
        root.createDirPath(io, dir) catch return false;
        root.writeFile(io, .{ .sub_path = try arena.print("{s}/.gitignore", .{dir}), .data = ignore }) catch return false;
    }
    for (files) |f| {
        const path = f.path[prefix.len..];
        if (!inDir(path, dir)) continue;
        if (try same(io, arena, root, path, f.data)) continue;
        if (Io.Dir.path.dirnamePosix(path)) |parent| root.createDirPath(io, parent) catch return false;
        root.writeFile(io, .{ .sub_path = path, .data = f.data }) catch return false;
    }
    return true;
}

fn same(io: Io, arena: std.mem.Allocator, root: Io.Dir, path: []const u8, data: []const u8) std.mem.Allocator.Error!bool {
    const have = root.readFileAlloc(io, path, arena, .limited(1 << 28)) catch return false;
    return std.mem.eql(u8, have, data);
}

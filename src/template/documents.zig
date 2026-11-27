//! The document skeletons of the templates a project uses (their
//! `documents/`, written under `docs/`): `skein template documents` writes
//! those not there yet, as when a template is brought along once an option
//! is given (`[[includes]]`), and `check` says of a template brought along that has
//! none of its documents in the project (#264).

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const Template = @import("Template.zig");
const files = @import("../files.zig");
const use = @import("use.zig");

const prefix = "documents/";

/// Writes the skeletons of `u` that the project has not, with its options;
/// the number written
pub fn write(io: Io, arena: std.mem.Allocator, root: Io.Dir, u: use.Use) !usize {
    var written: usize = 0;
    for (try Template.filesOf(arena, u.name, prefix)) |f| {
        const path = try arena.print("docs/{s}", .{f.path[prefix.len..]});
        if (try files.writeNew(io, root, path, try Template.substitute(arena, f.data, u.options))) written += 1;
    }
    return written;
}

/// Warns of each template brought along none of whose skeletons is in the
/// project, as when an option has just brought it
pub fn check(io: Io, arena: std.mem.Allocator, root: Io.Dir, project: *const Project, report: *Report) std.mem.Allocator.Error!void {
    for (project.templates) |u| {
        // one the project names itself may be used for its types alone
        const by = u.brought_by orelse continue;
        const skeletons = try Template.filesOf(arena, u.name, prefix);
        if (skeletons.len == 0) continue;
        const any = for (skeletons) |f| {
            const path = try arena.print("docs/{s}", .{f.path[prefix.len..]});
            if (root.access(io, path, .{})) |_| break true else |_| {}
        } else false;
        if (any) continue;
        try report.warn(Project.config_file, 0, 0, "the template {s}, which {s} brings along, has none of its {d} documents in docs/: skein template documents writes them", .{ u.name, by, skeletons.len });
    }
}

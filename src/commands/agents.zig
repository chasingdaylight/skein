//! `skein agents`: writes what coding agents should know of the project's
//! skein documents into its agent instructions file (`AGENTS.md`, or
//! `CLAUDE.md` where there is one; `--file` names another), in a section
//! that is written again in place; with `--skill`, as a skill file.

const std = @import("std");
const Io = std.Io;

const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");
const instructions = @import("../agents/instructions.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Agents) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    const file = try write(io, arena, &ws, options.skill, options.file);
    return .{ .text = try arena.print("skein: wrote what agents should know of Skein into {s}\n", .{file}) };
}

/// Writes the section, or the skill file; the path written
pub fn write(io: Io, arena: std.mem.Allocator, ws: *const Workspace, as_skill: bool, file: ?[]const u8) ![]const u8 {
    const text = try instructions.body(arena, &ws.project);
    if (as_skill) {
        const path = file orelse instructions.skill_file;
        if (Io.Dir.path.dirnamePosix(path)) |parent| try ws.root.createDirPath(io, parent);
        try ws.root.writeFile(io, .{ .sub_path = path, .data = try instructions.skill(arena, text) });
        return path;
    }
    const path = file orelse instructions.targetOf(io, ws.root);
    const existing = ws.root.readFileAlloc(io, path, arena, .limited(1 << 24)) catch |e| switch (e) {
        error.FileNotFound => "",
        else => return e,
    };
    // the line ends the file has
    const crlf = std.mem.find(u8, existing, "\r\n") != null;
    var merged = try instructions.merge(arena, try std.mem.replaceOwned(u8, arena, existing, "\r\n", "\n"), text);
    if (crlf) merged = try std.mem.replaceOwned(u8, arena, merged, "\n", "\r\n");
    try ws.root.writeFile(io, .{ .sub_path = path, .data = merged });
    return path;
}

test {
    _ = instructions;
    _ = @import("_test/agents.zig");
}

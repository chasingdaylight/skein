//! The workflow `skein init` writes for a project on GitHub (#266):
//! `.github/workflows/skein.yml` at the top of the repository, which checks
//! the documents and collects them as PDFs in `engineering-docs.zip` with
//! Skein's action. Written only where the repository's `origin` is on GitHub
//! and there is no such file yet.

const std = @import("std");
const Io = std.Io;

const git = @import("../git.zig");

/// The workflow's path when it was written; null when it was not
pub fn write(io: Io, arena: std.mem.Allocator, root: Io.Dir, version: []const u8) !?[]const u8 {
    const origin = try git.output(io, arena, root, &.{ "remote", "get-url", "origin" }) orelse return null;
    if (std.mem.find(u8, origin, "github.com") == null) return null;
    const top_out = try git.output(io, arena, root, &.{ "rev-parse", "--show-toplevel" }) orelse return null;
    const top = std.mem.trim(u8, top_out, " \r\n");
    const prefix_out = try git.output(io, arena, root, &.{ "rev-parse", "--show-prefix" }) orelse "";
    const prefix = std.mem.trimEnd(u8, std.mem.trim(u8, prefix_out, " \r\n"), "/");
    const path = try Io.Dir.path.join(arena, &.{ top, ".github", "workflows", "skein.yml" });
    if (Io.Dir.cwd().access(io, path, .{})) |_| return null else |_| {}
    const dir = Io.Dir.path.dirname(path) orelse return null;
    Io.Dir.cwd().createDirPath(io, dir) catch return null;
    Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = try text(arena, version, if (prefix.len > 0) prefix else ".") }) catch return null;
    return ".github/workflows/skein.yml";
}

pub fn text(arena: std.mem.Allocator, version: []const u8, project_root: []const u8) ![]const u8 {
    return arena.print(
        \\# Checks the project's Skein documents and collects them as PDFs, with
        \\# the coverage, in engineering-docs.zip, an artifact of each run. Written
        \\# by skein init; see Skein's docs/commands.md, "In continuous integration".
        \\name: Engineering documents
        \\
        \\on:
        \\  push:
        \\  pull_request:
        \\  workflow_dispatch:
        \\
        \\permissions:
        \\  contents: read
        \\
        \\jobs:
        \\  skein:
        \\    runs-on: ubuntu-24.04
        \\    steps:
        \\      - uses: actions/checkout@v7
        \\      - uses: chasingdaylight/skein@v{s}
        \\        with:
        \\          root: {s}
        \\
    , .{ version, project_root });
}

// req: ci.engineering-docs
test "the workflow uses Skein's action at this version, on the project's directory" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const t = try text(arena.allocator(), "0.2.0", "spec");
    try std.testing.expect(std.mem.find(u8, t, "      - uses: chasingdaylight/skein@v0.2.0\n        with:\n          root: spec\n") != null);
}

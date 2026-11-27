//! What `skein check` warns of when the project's files changed other than
//! the way it chose for them (`[serve] save`, serve/Workflow.zig; #280): it
//! cannot be enforced in a checkout, so it is said, never refused
//! (emanspeaks, 2026-11-27). From the commit that set `save` on:
//!
//! - `commit` with `editors`: a commit to the sources by someone not listed
//! - `branch`, `pull-request`: a commit straight on the branch changes go
//!   to, not merged from a change (a squashed pull request, `(#12)` at the
//!   end of its subject, counts as merged)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Project = @import("../Project.zig");
const Report = @import("../Report.zig");
const changes = @import("changes.zig");
const git = @import("../git.zig");

pub fn run(io: Io, a: Allocator, root: Io.Dir, project: *const Project, report: *Report) !void {
    const w = project.workflow;
    const save = w.save orelse return;
    // the branch checked out must be the one changes go to
    const branch = try changes.current(io, a, root) orelse return;
    if (changes.changeOf(branch) != null) return;
    if (w.branch) |b| if (!std.mem.eql(u8, b, branch)) return;
    const since_out = try git.output(io, a, root, &.{ "log", "-1", "--format=%H", "-G", "^[[:space:]]*save[[:space:]]*=", "--", Project.config_file }) orelse return;
    const since = std.mem.trim(u8, since_out, " \r\n");
    if (since.len == 0) return;
    const range = try a.print("{s}..HEAD", .{since});

    var args: std.ArrayList([]const u8) = .empty;
    switch (save) {
        .commit => {
            if (w.editors.len == 0) return;
            try args.appendSlice(a, &.{ "log", "--format=%an", range, "--" });
        },
        .branch, .@"pull-request" => try args.appendSlice(a, &.{ "log", "--first-parent", "--no-merges", "--format=%h %s", range, "--" }),
    }
    for (project.sources) |s| if (!s.read_only) try args.append(a, s.path);
    const out = try git.output(io, a, root, args.items) orelse return;
    var lines = std.mem.tokenizeAny(u8, out, "\r\n");

    switch (save) {
        .commit => {
            var counts: std.array_hash_map.String(usize) = .empty;
            while (lines.next()) |author| {
                if (listed(w.editors, author)) continue;
                const e = try counts.getOrPut(a, author);
                if (!e.found_existing) e.value_ptr.* = 0;
                e.value_ptr.* += 1;
            }
            for (counts.keys(), counts.values()) |author, n| {
                try report.warn(Project.config_file, 0, 0, "serve: {d} commit{s} by {s} changed the sources, who is not one of [serve] editors", .{ n, if (n == 1) "" else "s", author });
            }
        },
        .branch, .@"pull-request" => {
            var n: usize = 0;
            var latest: []const u8 = "";
            while (lines.next()) |line| {
                if (squashed(line)) continue;
                if (n == 0) latest = line;
                n += 1;
            }
            if (n > 0) try report.warn(Project.config_file, 0, 0, "serve: {d} commit{s} changed the sources straight on {s}, not through a change (save = \"{t}\"); the latest: {s}", .{ n, if (n == 1) "" else "s", branch, save, latest });
        },
    }
}

fn listed(editors: []const []const u8, name: []const u8) bool {
    for (editors) |e| if (std.mem.eql(u8, e, name)) return true;
    return false;
}

/// Whether a commit's subject ends as a squashed pull request's does: `(#12)`
fn squashed(line: []const u8) bool {
    const t = std.mem.trimEnd(u8, line, " ");
    if (!std.mem.endsWith(u8, t, ")")) return false;
    const open = std.mem.findLast(u8, t, "(#") orelse return false;
    const digits = t[open + 2 .. t.len - 1];
    if (digits.len == 0) return false;
    for (digits) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

test squashed {
    try std.testing.expect(squashed("a1b2c3 Fix the lexer (#12)"));
    try std.testing.expect(!squashed("a1b2c3 Fix the lexer"));
    try std.testing.expect(!squashed("a1b2c3 Fix (#x)"));
}

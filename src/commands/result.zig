//! `skein result ITEM pass|fail|skip`: records a result that a person
//! obtained, such as a procedure of a test plan carried out by hand: who,
//! when, at which commit, a note, and the fingerprints of the item and of
//! what it links to, so the result is stale once one of them changes. It
//! is appended to the results the project keeps.

const std = @import("std");
const Io = std.Io;

const Project = @import("../Project.zig");
const Reviews = @import("../graph/Reviews.zig");
const Workspace = @import("Workspace.zig");
const approve = @import("approve.zig");
const cli = @import("../cli.zig");
const git = @import("../git.zig");
const read = @import("../results/read.zig");
const write = @import("../toml/write.zig");

/// The file a recorded result goes to, in a results directory
pub const recorded_file = "recorded.toml";

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Result) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const item = ws.graph.find(options.id) orelse return misuse(arena, "there is no item '{s}'", .{options.id});
    const first = if (ws.project.results.len > 0) ws.project.results[0] else return misuse(arena, "the project keeps no results: name where, with [results] paths in {s}", .{Project.config_file});
    // a directory gets a file of its own; a file is to be TOML
    const file = if (read.formatOf(first)) |format|
        (if (format == .toml) first else return misuse(arena, "results are recorded in TOML: the first of [results] paths is to be a directory or a .toml file", .{}))
    else
        try arena.print("{s}/{s}", .{ first, recorded_file });
    const by = options.by orelse try git.userName(io, arena, ws.root) orelse return misuse(arena, "who obtained it? Give --by NAME (git has no user.name to take it from)", .{});
    const on = if (options.on) |text| approve.parseDate(text) orelse return misuse(arena, "'{s}' is no date; write it like 2027-03-01", .{text}) else approve.today(io);
    const commit = std.mem.trim(u8, try git.output(io, arena, ws.root, &.{ "rev-parse", "HEAD" }) orelse "", " \r\n");

    // what was verified, as it is now
    var prints: std.ArrayList([]const u8) = .empty;
    const schema = &ws.project.schema;
    if (try Reviews.targetFingerprint(arena, schema, &ws.graph, item.id)) |fp| try prints.append(arena, try arena.print("{s}={s}", .{ item.id, &fp }));
    for (item.links) |link| {
        const fp = try Reviews.targetFingerprint(arena, schema, &ws.graph, link.target) orelse continue;
        try prints.append(arena, try arena.print("{s}={s}", .{ link.target, &fp }));
    }

    var text: std.ArrayList(u8) = .empty;
    try text.print(arena, "\n[[result]]\nitem = {s}\nresult = \"{s}\"\nby = {s}\ndate = {d:0>4}-{d:0>2}-{d:0>2}\n", .{ try write.string(arena, item.id), @tagName(options.outcome), try write.string(arena, by), on.year, on.month, on.day });
    if (commit.len > 0) try text.print(arena, "commit = {s}\n", .{try write.string(arena, commit)});
    if (options.implementation) |v| try text.print(arena, "implementation = {s}\n", .{try write.string(arena, v)});
    if (options.note) |n| try text.print(arena, "note = {s}\n", .{try write.string(arena, n)});
    try text.print(arena, "fingerprints = {s}\n", .{try write.strings(arena, prints.items)});

    const old = ws.root.readFileAlloc(io, file, arena, .limited(1 << 26)) catch |e| switch (e) {
        error.FileNotFound => "# Results recorded with 'skein result'.\n",
        else => return misuse(arena, "cannot read {s} ({s})", .{ file, @errorName(e) }),
    };
    if (Io.Dir.path.dirnamePosix(file)) |dir| ws.root.createDirPath(io, dir) catch |e| return misuse(arena, "cannot make {s} ({s})", .{ dir, @errorName(e) });
    ws.root.writeFile(io, .{ .sub_path = file, .data = try std.mem.concat(arena, u8, &.{ old, text.items }) }) catch |e|
        return misuse(arena, "cannot write {s} ({s})", .{ file, @errorName(e) });
    const verb = switch (options.outcome) {
        .pass => "passed",
        .fail => "failed",
        .skip => "was skipped",
    };
    return .{ .text = try arena.print("skein: recorded that {s} {s}, by {s}, in {s}\n", .{ item.id, verb, by, file }) };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

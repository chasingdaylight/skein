//! `skein approve ID...`: record that someone approved these items as
//! they are now.

const std = @import("std");
const Io = std.Io;

const Approvals = @import("../graph/Approvals.zig");
const cli = @import("../cli.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const datetime = @import("../toml/datetime.zig");
const git = @import("../git.zig");
const toml = @import("../toml.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Approve) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();

    const by = options.by orelse try git.userName(io, arena, ws.root) orelse return .{
        .text = "skein: who approves? Give --by NAME (git has no user.name to take it from)\n",
        .status = .misuse,
    };
    const on = if (options.on) |text| parseDate(text) orelse return .{
        .text = try arena.print("skein: '{s}' is no date; write it like 2027-03-01\n", .{text}),
        .status = .misuse,
    } else today(io);

    for (options.ids) |id| {
        if (ws.graph.find(id) == null) return .{
            .text = try arena.print("skein: there is no item '{s}'\n", .{id}),
            .status = .misuse,
        };
    }
    // the records must be readable, or writing them again would lose some
    const before = ws.report.problems.items.len;
    var approvals = try Approvals.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();

    var files: std.ArrayList([]const u8) = .empty;
    for (options.ids) |id| {
        const item = ws.graph.find(id).?;
        const item_type = ws.project.schema.itemType(item.type_name) orelse return .{
            .text = try arena.print("skein: '{s}' is of a type the schema does not have\n", .{id}),
            .status = .misuse,
        };
        try approvals.put(arena, item, item_type, by, on);
        const file = try Approvals.fileOf(arena, item);
        if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
    }
    try approvals.write(io, arena, ws.root, &ws.graph, files.items);
    const n = options.ids.len;
    return .{
        .text = try arena.print("skein: {d} item{s} approved by {s} on {d:0>4}-{d:0>2}-{d:0>2}\n", .{ n, if (n == 1) "" else "s", by, on.year, on.month, on.day }),
    };
}

fn parseDate(text: []const u8) ?toml.Date {
    if (text.len != 10) return null;
    const dt = datetime.parse(text) orelse return null;
    return dt.date;
}

/// Today's date, in UTC
fn today(io: Io) toml.Date {
    const seconds: u64 = @intCast(@max(0, Io.Clock.real.now(io).toSeconds()));
    const day = (std.time.epoch.EpochSeconds{ .secs = seconds }).getEpochDay().calculateYearDay();
    const month = day.calculateMonthDay();
    return .{ .year = day.year, .month = month.month.numeric(), .day = @as(u8, month.day_index) + 1 };
}

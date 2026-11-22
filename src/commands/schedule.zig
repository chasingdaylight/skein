//! `skein schedule`: computes the schedule of the work items and writes it
//! to `.skein/schedule.toml` (and the formats `[schedule] also` names),
//! and writes `float` into the float items that name no mode, so that from
//! then on every item gives its mode.

const std = @import("std");
const Io = std.Io;

const Calendar = @import("../planning/Calendar.zig");
const Resources = @import("../planning/Resources.zig");
const Work = @import("../planning/Work.zig");
const Workspace = @import("Workspace.zig");
const attribute = @import("../edit/attribute.zig");
const cli = @import("../cli.zig");
const schedule = @import("../planning/schedule.zig");
const stored = @import("../planning/stored.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Schedule) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    const before = ws.report.problems.items.len;
    const resources = try Resources.load(io, arena, ws.root, &ws.report);
    if (ws.report.problems.items.len > before) return ws.problems();
    const calendar: *const Calendar = if (resources) |*r| &r.calendar else &Calendar.every_day;

    const works = try Work.collect(arena, &ws.project.schema, &ws.graph);
    if (works.len == 0) return .{ .text = try arena.print("skein: there are no work items: no item type has [planning]\n", .{}), .status = .misuse };
    const entries = try schedule.compute(arena, works, calendar);

    var out: std.ArrayList(u8) = .empty;
    // the mode, where the type has one and the item names none
    var marked: usize = 0;
    var by_hand: std.ArrayList([]const u8) = .empty;
    for (entries) |*e| {
        if (e.mode != .float or e.work.written_mode != null) continue;
        const item = e.work.item;
        const t = ws.project.schema.itemType(item.type_name).?;
        const key = t.planning.?.attribute(.mode) orelse continue;
        if (ws.project.readOnlySource(item.file) != null) continue;
        const text = try ws.root.readFileAlloc(io, item.file, arena, .limited(1 << 26));
        const edited = (if (item.in_document) try attribute.marker(arena, text, item.line, key, "float") else try attribute.frontMatter(arena, text, key, "\"float\"")) orelse {
            try by_hand.append(arena, item.id);
            continue;
        };
        try ws.root.writeFile(io, .{ .sub_path = item.file, .data = edited });
        marked += 1;
    }

    try ws.root.writeFile(io, .{ .sub_path = stored.toml_file, .data = try stored.toml(arena, entries) });
    var files: std.ArrayList([]const u8) = .empty;
    try files.append(arena, stored.toml_file);
    for (ws.project.schedule_also) |format| {
        const data = if (std.mem.eql(u8, format, "json")) try stored.json(arena, entries) else try stored.csv(arena, entries);
        try ws.root.writeFile(io, .{ .sub_path = stored.fileOf(format), .data = data });
        try files.append(arena, stored.fileOf(format));
    }

    var critical: usize = 0;
    var unscheduled: usize = 0;
    for (entries) |*e| {
        if (e.critical()) critical += 1;
        if (e.source == .unscheduled) unscheduled += 1;
    }
    try out.print(arena, "skein: {d} work items scheduled, {d} on the critical path", .{ entries.len - unscheduled, critical });
    if (unscheduled > 0) try out.print(arena, "; {d} cannot be scheduled", .{unscheduled});
    try out.print(arena, "; wrote {s}\n", .{try std.mem.join(arena, ", ", files.items)});
    if (marked > 0) try out.print(arena, "skein: wrote the mode float into {d} items that named none\n", .{marked});
    if (by_hand.items.len > 0) try out.print(arena, "skein: write the mode float by hand into {s}\n", .{try std.mem.join(arena, ", ", by_hand.items)});
    return .{ .text = out.items };
}

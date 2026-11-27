//! `skein approve ID...`: record that someone approved these items as
//! they are now.

const std = @import("std");
const Io = std.Io;

const Approvals = @import("../graph/Approvals.zig");
const approve_pull = @import("approve_pull.zig");
const cli = @import("../cli.zig");
const Schema = @import("../schema/Schema.zig");
const Workspace = @import("Workspace.zig");
const datetime = @import("../toml/datetime.zig");
const git = @import("../git.zig");
const signatures = @import("../graph/signatures.zig");
const toml = @import("../toml.zig");

pub fn run(io: Io, arena: std.mem.Allocator, options: cli.Approve) !Workspace.Outcome {
    var ws = switch (try Workspace.open(io, arena, options.common)) {
        .ok => |ws| ws,
        .failed => |outcome| return outcome,
    };
    defer ws.close();
    if (!ws.items_read) return ws.problems();
    if (options.from_pull_request) |number| return approve_pull.run(io, arena, &ws, number);

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
        // a type that names roles is approved in one of them
        const roles = item_type.approval_roles;
        if (options.as) |role| {
            if (!Schema.names.contains(roles, role)) return .{
                .text = try arena.print("skein: '{s}' is no role that approves a '{s}'{s}{s}\n", .{ role, item.type_name, if (roles.len > 0) ": " else "", try std.mem.join(arena, ", ", roles) }),
                .status = .misuse,
            };
        } else if (roles.len > 0) return .{
            .text = try arena.print("skein: say in which role {s} approves '{s}': --as {s}\n", .{ by, id, try std.mem.join(arena, "|", roles) }),
            .status = .misuse,
        };
        // the type may say who approves; an approval by anyone else would not count
        const who = Approvals.approversOf(item_type, options.as);
        if (who.len > 0 and !Schema.names.contains(who, by)) return .{
            .text = try arena.print("skein: {s} may not approve '{s}'{s}{s}; those who may: {s}\n", .{ by, id, if (options.as != null) " as " else "", options.as orelse "", try std.mem.join(arena, ", ", who) }),
            .status = .misuse,
        };
        try approvals.put(arena, &ws.graph, &ws.project.schema, item, by, on, options.as, .{ .signed_in = options.signed_in });
        const file = try Approvals.fileOf(arena, item);
        if (!Schema.names.contains(files.items, file)) try files.append(arena, file);
    }
    try approvals.write(io, arena, ws.root, &ws.graph, files.items);
    const n = options.ids.len;
    const said = try arena.print("skein: {d} item{s} approved by {s}{s} on {d:0>4}-{d:0>2}-{d:0>2}\n", .{ n, if (n == 1) "" else "s", by, if (options.as) |r| try arena.print(" as {s}", .{r}) else "", on.year, on.month, on.day });
    if (options.sign) {
        // the signature is the commit's: of the records alone
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(arena, &.{ "add", "--" });
        try args.appendSlice(arena, files.items);
        switch (try git.run(io, arena, ws.root, args.items)) {
            .ok => {},
            .failed => |why| return .{ .text = try arena.print("{s}skein: the approval is written, and not committed: {s}\n", .{ said, why }), .status = .problems },
        }
        args.clearRetainingCapacity();
        try args.appendSlice(arena, &.{ "commit", "--quiet", "-S", "-m", try arena.print("Approve {s}", .{try std.mem.join(arena, ", ", options.ids)}), "--" });
        try args.appendSlice(arena, files.items);
        return switch (try git.run(io, arena, ws.root, args.items)) {
            .ok => .{ .text = try arena.print("{s}skein: committed, signed\n", .{said}) },
            .failed => |why| .{ .text = try arena.print("{s}skein: the approval is written, and not committed signed: {s}\n", .{ said, why }), .status = .problems },
        };
    }
    // a type that asks for signed approvals: say how
    for (options.ids) |id| {
        const item_type = ws.project.schema.itemType(ws.graph.find(id).?.type_name).?;
        if (signatures.needed(item_type, options.as)) return .{ .text = try arena.print("{s}skein: these approvals must be signed: commit them with git commit -S, or approve with --sign\n", .{said}) };
    }
    return .{ .text = said };
}

pub fn parseDate(text: []const u8) ?toml.Date {
    if (text.len != 10) return null;
    const dt = datetime.parse(text) orelse return null;
    return dt.date;
}

/// Today's date, in UTC
pub fn today(io: Io) toml.Date {
    const seconds: u64 = @intCast(@max(0, Io.Clock.real.now(io).toSeconds()));
    const day = (std.time.epoch.EpochSeconds{ .secs = seconds }).getEpochDay().calculateYearDay();
    const month = day.calculateMonthDay();
    return .{ .year = day.year, .month = month.month.numeric(), .day = @as(u8, month.day_index) + 1 };
}

//! Burndown and burnup charts a document asks for, as Mermaid `xychart`
//! diagrams with a table of the days under them, as GitLab draws them:
//!
//!     ```skein
//!     burndown MILESTONE [weight] [from=DATE] [to=DATE]
//!     burnup MILESTONE [weight] [from=DATE] [to=DATE]
//!     ```
//!
//! The milestone is the work item that the `milestone` role of the work
//! names. Its days run from `from` (else the first start of its work) to
//! `to` (else its finish), up to today. The burndown shows what remains
//! beside a straight guideline from the starting total to zero; the burnup
//! the scope and what is done, so that work added during the milestone is
//! seen as scope, not as lost progress. `weight` counts each item's
//! estimate (else its duration) in place of one each.

// cspell:ignore xychart nxychart
const std = @import("std");

const burn = @import("../planning/burn.zig");
const day = @import("../planning/day.zig");
const gantt = @import("gantt.zig");
const generated = @import("generated.zig");

const Error = generated.Error;

pub const Kind = enum { burndown, burnup };

pub fn render(ctx: generated.Context, kind: Kind, args: []const []const u8) Error![]const u8 {
    const a = ctx.arena;
    const plan = ctx.planning orelse return a.print("> **skein:** the plan is not drawn here\n", .{});
    if (args.len == 0) return a.print("> **skein:** {t} needs a milestone: {t} MILESTONE\n", .{ kind, kind });
    const milestone = args[0];
    var count: burn.Count = .items;
    var from: ?day.Day = null;
    var to: ?day.Day = null;
    for (args[1..]) |word| {
        if (std.mem.eql(u8, word, "weight")) {
            count = .weight;
        } else if (std.mem.startsWith(u8, word, "from=")) {
            from = day.parse(word["from=".len..]) orelse return a.print("> **skein:** '{s}' is no date\n", .{word["from=".len..]});
        } else if (std.mem.startsWith(u8, word, "to=")) {
            to = day.parse(word["to=".len..]) orelse return a.print("> **skein:** '{s}' is no date\n", .{word["to=".len..]});
        } else return a.print("> **skein:** {t} takes a milestone, weight, from=DATE and to=DATE, not '{s}'\n", .{ kind, word });
    }
    // the milestone's days: from the first start of its work to its finish
    for (plan.entries) |e| {
        if (to == null and std.mem.eql(u8, e.work.item.id, milestone)) to = e.finish;
        const m = e.work.milestone orelse continue;
        if (!std.mem.eql(u8, m, milestone)) continue;
        if (e.start) |s| if (from == null or s < from.?) {
            from = s;
        };
    }
    const first = from orelse return a.print("> **skein:** the days of '{s}' are not known: no work of it has a start; give from=DATE\n", .{milestone});
    const last = to orelse return a.print("> **skein:** the days of '{s}' are not known: it is no work item with a finish; give to=DATE\n", .{milestone});
    if (last < first) return a.print("> **skein:** the days of '{s}' end before they begin\n", .{milestone});
    if (first > plan.today) return a.print("*The milestone `{s}` begins on {s}.*\n", .{ milestone, &day.format(first) });
    const points = try plan.burn(plan.baseline_ctx, milestone, first, last, count);
    if (points.len == 0) return a.print("> **skein:** the history of '{s}' could not be read\n", .{milestone});

    const unit = if (count == .weight) "Days of work" else "Items";
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "```mermaid\nxychart-beta\n  title \"{s} of {s}\"\n  x-axis [", .{ if (kind == .burndown) "Burndown" else "Burnup", milestone });
    for (points, 0..) |p, i| try out.print(a, "{s}\"{s}\"", .{ if (i > 0) ", " else "", (&day.format(p.day))[5..] });
    var top: f64 = 1;
    for (points) |p| top = @max(top, p.total);
    try out.print(a, "]\n  y-axis \"{s}\" 0 --> {s}\n", .{ unit, try number(a, top) });
    const span: f64 = @floatFromInt(@max(1, last - first));
    const start_total = points[0].total;
    switch (kind) {
        .burndown => {
            try line(a, &out, points, struct {
                fn f(p: burn.Point) f64 {
                    return p.total - p.done;
                }
            }.f);
            // the guideline: the starting total down to none on the last day
            try out.appendSlice(a, "  line [");
            for (points, 0..) |p, i| {
                const g = @max(0, start_total * (1 - @as(f64, @floatFromInt(p.day - first)) / span));
                try out.print(a, "{s}{s}", .{ if (i > 0) ", " else "", try number(a, g) });
            }
            try out.appendSlice(a, "]\n");
        },
        .burnup => {
            try line(a, &out, points, struct {
                fn f(p: burn.Point) f64 {
                    return p.total;
                }
            }.f);
            try line(a, &out, points, struct {
                fn f(p: burn.Point) f64 {
                    return p.done;
                }
            }.f);
        },
    }
    try out.appendSlice(a, "```\n\n");
    try out.appendSlice(a, switch (kind) {
        .burndown => "The first line is what remains, the second the guideline from the starting total to none on the last day.\n\n",
        .burnup => "The first line is the scope, the second what is done.\n\n",
    });
    try out.print(a, "| Day | Scope | Done | Remaining |\n| --- | ---: | ---: | ---: |\n", .{});
    for (points) |p| try out.print(a, "| {s} | {s} | {s} | {s} |\n", .{ &day.format(p.day), try number(a, p.total), try number(a, p.done), try number(a, p.total - p.done) });
    return out.items;
}

fn line(a: std.mem.Allocator, out: *std.ArrayList(u8), points: []const burn.Point, value: fn (burn.Point) f64) Error!void {
    try out.appendSlice(a, "  line [");
    for (points, 0..) |p, i| try out.print(a, "{s}{s}", .{ if (i > 0) ", " else "", try number(a, value(p)) });
    try out.appendSlice(a, "]\n");
}

/// A whole number as it is, another with one decimal
fn number(a: std.mem.Allocator, v: f64) Error![]const u8 {
    if (v == @round(v)) return a.print("{d}", .{@as(i64, @intFromFloat(v))});
    return a.print("{d:.1}", .{v});
}

test {
    _ = gantt;
}

//! `skein template list` and `skein template show NAME`: the templates
//! built into skein, and what one declares.

const std = @import("std");

const Template = @import("../template/Template.zig");
const Workspace = @import("Workspace.zig");
const cli = @import("../cli.zig");

pub fn run(arena: std.mem.Allocator, options: cli.TemplateCommand) !Workspace.Outcome {
    var out: std.ArrayList(u8) = .empty;
    switch (options.what) {
        .list => for (try Template.names(arena)) |name| {
            try out.print(arena, "{s}  {s}\n", .{ name, (try Template.info(arena, name)).description });
        },
        .show => {
            const name = options.name orelse return misuse(arena, "template show takes the name of a template", .{});
            if (!Template.exists(name)) return misuse(arena, "skein has no template '{s}' ('skein template list' names them)", .{name});
            const info = try Template.info(arena, name);
            try out.print(arena, "{s}: {s}\n", .{ name, info.description });
            if (info.options.len > 0) try out.appendSlice(arena, "\nOptions:\n");
            for (info.options) |o| {
                try out.print(arena, "  {s}", .{o.name});
                if (o.values.len > 0) try out.print(arena, " ({s})", .{try std.mem.join(arena, ", ", o.values)});
                if (o.default) |d| try out.print(arena, ", default {s}", .{d});
                try out.print(arena, ": {s}\n", .{o.description});
            }
            for ([_][]const u8{ "types", "links", "profiles", "documents" }) |kind| {
                const files = try Template.filesOf(arena, name, try arena.print("{s}/", .{kind}));
                if (files.len == 0) continue;
                try out.print(arena, "\n{c}{s}:\n", .{ std.ascii.toUpper(kind[0]), kind[1..] });
                for (files) |f| try out.print(arena, "  {s}\n", .{f.path[kind.len + 1 ..]});
            }
        },
    }
    return .{ .text = out.items };
}

fn misuse(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !Workspace.Outcome {
    return .{ .text = try arena.print("skein: " ++ fmt ++ "\n", args), .status = .misuse };
}

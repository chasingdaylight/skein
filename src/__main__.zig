const std = @import("std");

const check = @import("commands/check.zig");
const cli = @import("cli.zig");
const review = @import("commands/review.zig");
const stdio = @import("stdio.zig");
const Workspace = @import("commands/Workspace.zig");

const version = @import("build_options").version;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

    const outcome: Workspace.Outcome = switch (try cli.parse(arena, argv[1..])) {
        .help => .{ .text = cli.usage },
        .version => .{ .text = version ++ "\n" },
        .check => |options| try check.run(io, arena, options),
        .review => |options| try review.run(io, arena, options, .from),
        .clear => |options| try review.run(io, arena, options, .to),
        .unknown => |name| .{
            .text = try arena.print("skein: unknown command '{s}'\n\n{s}", .{ name, cli.usage }),
            .status = .misuse,
        },
        .misuse => |problem| .{
            .text = try arena.print("skein: {s}\n\n{s}", .{ problem, cli.usage }),
            .status = .misuse,
        },
    };
    if (outcome.status == .ok) return stdio.stdout().writeStreamingAll(io, outcome.text);
    try stdio.stderr().writeStreamingAll(io, outcome.text);
    std.process.exit(@backingInt(outcome.status));
}
